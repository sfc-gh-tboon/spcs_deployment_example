# STEP 1 - Create Image Repository
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 1 - Create Image Repository"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA"
if (-not $result) { Write-Host "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1 }
Write-Host "    [OK] Role $ROLE and schema $DB.$SCHEMA accessible"

Write-Host "`n==> Creating image repository $REPO_NAME..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE IMAGE REPOSITORY IF NOT EXISTS $REPO_NAME;"

Write-Host "`n==> Repository URL:"
$repos = Invoke-SnowSql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA"
if ($repos -and $repos.Count -gt 0) {
    $repoUrl = $repos[0].repository_url
    Write-Host "    $repoUrl"
} else {
    Write-Host "WARNING: Could not parse repository URL."
}

if ($SERVICE_ROLE -ne $ROLE) {
    Write-Host "`n==> Granting READ on $REPO_NAME to $SERVICE_ROLE..."
    Invoke-SnowSqlDisplay "USE ROLE $ROLE; GRANT READ ON IMAGE REPOSITORY $DB.$SCHEMA.$REPO_NAME TO ROLE $SERVICE_ROLE;"
}

Write-Host "`n==========================================================================="
Write-Host " STEP 1 COMPLETE - Image repository ready"
Write-Host "==========================================================================="

exit 0
