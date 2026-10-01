# STEP 4 - Create Secret
. "$PSScriptRoot\config.ps1"

$tokenValue = [Environment]::GetEnvironmentVariable("API_SECRET")
if (-not $tokenValue) { $tokenValue = $script:ConfigCache["API_SECRET"] }
if (-not $tokenValue) {
    $input = Read-Host "API bearer token [dummy-token-for-testing]"
    $tokenValue = if ($input) { $input } else { "dummy-token-for-testing" }
    $script:ConfigCache["API_SECRET"] = $tokenValue
}

Write-Host "`n==========================================================================="
Write-Host " STEP 4 - Create Secret"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA"
if (-not $result) { Write-Host "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1 }
Write-Host "    [OK] Role and schema accessible"

$secrets = Invoke-SnowSql "SHOW SECRETS LIKE '$SECRET_NAME' IN SCHEMA $DB.$SCHEMA"
if ($secrets -and $secrets.Count -gt 0) {
    Write-Host "WARNING: Secret $SECRET_NAME already exists. Using IF NOT EXISTS to avoid overwriting."
    Write-Host "         To update: ALTER SECRET $SECRET_NAME SET SECRET_STRING = 'new-value';"
}

Write-Host "`n==> Creating secret $SECRET_NAME..."
if ($tokenValue -eq "dummy-token-for-testing") {
    Write-Host "    Using DUMMY token value (set API_SECRET env var for real token)"
} else {
    Write-Host "    Using provided token value"
}

$safeTokenValue = $tokenValue -replace "'", "''"
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE SECRET IF NOT EXISTS $SECRET_NAME TYPE = GENERIC_STRING SECRET_STRING = '$safeTokenValue' COMMENT = 'API bearer token for the $SERVICE_NAME proxy service';"

if ($SERVICE_ROLE -ne $ROLE) {
    Write-Host "`n==> Granting READ on $SECRET_NAME to $SERVICE_ROLE..."
    Invoke-SnowSqlDisplay "USE ROLE $ROLE; GRANT READ ON SECRET $DB.$SCHEMA.$SECRET_NAME TO ROLE $SERVICE_ROLE;"
}

Write-Host "`n==========================================================================="
Write-Host " STEP 4 COMPLETE - Secret $SECRET_NAME created"
Write-Host "==========================================================================="

exit 0
