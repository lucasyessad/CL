#-----------------------------------------------------------------------------#
# SCHEDULE : -                                                                 #
#                                                                             #
# PROJET   : EXPORT / IMPORT BCP                                              #
#                                                                             #
# TITRE SCRIPT  : Chargement des fichiers BCP vers les tables cibles         #
#                                                                             #
# DATE CREATION : 23/07/2026                              MAJ  : 23/07/2026   #
#                                                         USER : -            #
#                                                                             #
#-----------------------------------------------------------------------------#
# OBJECTIF : Décompression des archives ZIP, puis chargement des fichiers     #
#            .bcp vers les tables cibles sur le serveur d'arrivée.           #
#                                                                             #
# CALL : ./import_bcpin.ps1                                                   #
#-----------------------------------------------------------------------------#

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigFile = "import-parameters.psd1",

    [Parameter()]
    [string]$Server,

    [Parameter()]
    [string]$Database,

    [Parameter()]
    [string]$InputDir,

    [Parameter()]
    [string[]]$Mappings,

    [Parameter()]
    [string]$TargetSchema,

    [Parameter()]
    [string]$TargetTablePrefix,

    [Parameter()]
    [string]$ListFileName,

    [Parameter()]
    [switch]$Truncate
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$Color = 'Cyan'
    )

    Write-Host $Message -ForegroundColor $Color
}

function Invoke-BcpExecution {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    & bcp @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "ERREUR $Operation (code $LASTEXITCODE)"
    }
}

if (-not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $PSScriptRoot $ConfigFile
}

if (-not (Test-Path -Path $ConfigFile)) {
    throw "Fichier de configuration introuvable : $ConfigFile"
}

$config = Import-PowerShellDataFile -Path $ConfigFile

if (-not $PSBoundParameters.ContainsKey('Server')) { $Server = $config.TargetServer }
if (-not $PSBoundParameters.ContainsKey('Database')) { $Database = $config.TargetDatabase }
if (-not $PSBoundParameters.ContainsKey('InputDir')) { $InputDir = $config.TargetInputDir }
if (-not $PSBoundParameters.ContainsKey('Mappings')) { $Mappings = $config.Mappings }
if (-not $PSBoundParameters.ContainsKey('TargetSchema')) { $TargetSchema = $config.TargetSchema }
if (-not $PSBoundParameters.ContainsKey('TargetTablePrefix')) { $TargetTablePrefix = $config.TargetTablePrefix }
if (-not $PSBoundParameters.ContainsKey('ListFileName')) { $ListFileName = $config.ListFileName }

if (-not $Mappings -or $Mappings.Count -eq 0) {
    $listFile = Join-Path $InputDir $ListFileName
    if (Test-Path -Path $listFile) {
        $Mappings = Get-Content -Path $listFile
    }
    else {
        $inputFiles = Get-ChildItem -Path $InputDir -Filter "*.bcp" | Sort-Object Name
        if ($inputFiles.Count -eq 0) {
            throw "Aucun fichier .bcp trouvé dans : $InputDir"
        }

        $Mappings = foreach ($file in $inputFiles) {
            [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        }
    }
}

if (-not (Test-Path -Path $InputDir)) {
    throw "Le répertoire d'import est introuvable : $InputDir"
}

$zipFiles = Get-ChildItem -Path $InputDir -Filter "*.zip" | Sort-Object Name
if ($zipFiles.Count -gt 0) {
    foreach ($zipFile in $zipFiles) {
        Expand-Archive -Path $zipFile.FullName -DestinationPath $InputDir -Force
        Write-Log -Message "Archive ZIP extraite : $($zipFile.FullName)"
    }
}

foreach ($entry in $Mappings) {
    $sourceTable = $entry
    $schema = $TargetSchema
    $targetTable = "$TargetTablePrefix$sourceTable"

    $inputFile = Join-Path $InputDir ("{0}.bcp" -f $sourceTable)

    if (-not (Test-Path -Path $inputFile)) {
        Write-Warning "Fichier introuvable : $inputFile"
        continue
    }

    $target = "$Database.$schema.$targetTable"

    if ($Truncate) {
        Write-Host "TRUNCATE TABLE $target" -ForegroundColor Yellow
        $truncateSql = "TRUNCATE TABLE [$schema].[$targetTable]"
        Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $truncateSql -ErrorAction Stop
    }

    Write-Log -Message "BCP IN depuis $inputFile vers $target"

    $args = @(
        $target,
        'in',
        $inputFile,
        '-n',
        '-S', $Server,
        '-T'
    )

    Invoke-BcpExecution -Arguments $args -Operation "import BCP pour $sourceTable"
}

Write-Log -Message "Import terminé !" -Color Green
