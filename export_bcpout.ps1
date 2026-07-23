#-----------------------------------------------------------------------------#
# SCHEDULE : -                                                                 #
#                                                                             #
# PROJET   : EXPORT / IMPORT BCP                                              #
#                                                                             #
# TITRE SCRIPT  : Extraction des vues vers fichiers BCP                       #
#                 et copie vers le répertoire d'import                        #
#                                                                             #
# DATE CREATION : 23/07/2026                              MAJ  : 23/07/2026   #
#                                                         USER : -            #
#                                                                             #
#-----------------------------------------------------------------------------#
# OBJECTIF : Export des vues SQL Server vers des fichiers binaires natifs      #
#            avec bcp, archivage ZIP et copie vers le répertoire cible.       #
#                                                                             #
# CALL : ./export_bcpout.ps1                                                 #
#-----------------------------------------------------------------------------#

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigFile = "export-parameters.psd1"
)

$ErrorActionPreference = 'Stop'

$config = Import-PowerShellDataFile -Path $ConfigFile

$Server = $config.SourceServer
$Database = $config.SourceDatabase
$Schema = $config.SourceSchema
$OutputDir = $config.SourceOutputDir
$ViewSchema = $config.SourceViewSchema
$ViewNamePattern = $config.SourceViewNamePattern
$ViewPriorityName = $config.SourceViewPriorityName
$TargetCopyDir = $config.TargetCopyDir
$SourceCopyDir = $config.SourceCopyDir
$CopyFilePattern = $config.CopyFilePattern
$CopyBatchFile = $config.CopyBatchFile
$ListFileName = $config.ListFileName

$Tables = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query @"
SELECT v.name
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE s.name = '$ViewSchema'
  AND v.name LIKE '$ViewNamePattern'
ORDER BY CASE WHEN v.name = '$ViewPriorityName' THEN 0 ELSE 1 END, v.name
"@ -ErrorAction Stop | Select-Object -ExpandProperty name

$targetListFile = Join-Path $OutputDir $ListFileName
if (Test-Path -Path $targetListFile) { Remove-Item -Path $targetListFile -Force }
Set-Content -Path $targetListFile -Value $Tables -Encoding UTF8

if (-not (Test-Path -Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

foreach ($table in $Tables) {
    $outputFile = Join-Path $OutputDir ("{0}.bcp" -f $table)
    Write-Host "BCP OUT de $outputFile" -ForegroundColor Cyan
    & bcp "$Database.$Schema.$table" out $outputFile -n -S $Server -T
    if ($LASTEXITCODE -ne 0) { throw "ERREUR export BCP pour $table" }
}

$zipFile = Join-Path $OutputDir ("{0}.zip" -f $Tables[0])
if (Test-Path -Path $zipFile) { Remove-Item -Path $zipFile -Force }

$filesToZip = @($targetListFile) + (Get-ChildItem -Path $OutputDir -Filter "*.bcp" | Select-Object -ExpandProperty FullName)
Compress-Archive -Path $filesToZip -DestinationPath $zipFile -Force

if (-not (Test-Path -Path $TargetCopyDir)) { New-Item -ItemType Directory -Path $TargetCopyDir -Force | Out-Null }
$env:datalib = $SourceCopyDir
$env:infile = Join-Path $SourceCopyDir $CopyFilePattern
$env:outfile = $TargetCopyDir
& $CopyBatchFile
Copy-Item -LiteralPath $zipFile -Destination $TargetCopyDir -Force
Write-Host "Export terminé" -ForegroundColor Green
