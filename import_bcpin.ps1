# ==========================================================
# IMPORT - a executer sur le serveur CIBLE
# Parcourt tous les fichiers Zbcp_*.csv du repertoire cible
# et fait un bcp in dans la table correspondante
# ==========================================================

$server   = "NOM_SERVEUR_CIBLE"
$database = "NOM_BASE_CIBLE"
$inDir    = "C:\Import"

$files = Get-ChildItem -Path $inDir -Filter "Zbcp_*.csv"

foreach ($file in $files) {

    $table = $file.BaseName -replace "^Zbcp_", ""

    bcp "$database.dbo.$table" in "$($file.FullName)" -c -t";" -S $server -T

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERREUR import table $table (code $LASTEXITCODE)" -ForegroundColor Red
    } else {
        Write-Host "OK import : $table" -ForegroundColor Green
    }
}
