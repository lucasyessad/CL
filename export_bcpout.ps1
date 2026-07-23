# ==========================================================
# EXPORT - a executer sur le serveur SOURCE
# Genere un fichier Zbcp_<table>.csv par table listee
# ==========================================================

$server   = "NOM_SERVEUR_SOURCE"
$database = "NOM_BASE_SOURCE"
$outDir   = "C:\Export"

$tables = @(
    "Table1",
    "Table2",
    "Table3"
)

foreach ($table in $tables) {

    $outFile = Join-Path $outDir "Zbcp_$table.csv"
    $query   = "SELECT * FROM $table"

    bcp "$query" queryout "$outFile" -c -t";" -S $server -d $database -T

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERREUR export table $table (code $LASTEXITCODE)" -ForegroundColor Red
    } else {
        Write-Host "OK export : $table -> $outFile" -ForegroundColor Green
    }
}
