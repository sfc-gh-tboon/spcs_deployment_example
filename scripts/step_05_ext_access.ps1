# STEP 5 - Create External Access Integration
# NOTE: Requires ACCOUNTADMIN (or CREATE INTEGRATION privilege)
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 5 - Create External Access Integration"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ADMIN_ROLE"
if (-not $result) {
    Write-Host "ERROR: Cannot switch to role $ADMIN_ROLE."
    Write-Host "       CREATE EXTERNAL ACCESS INTEGRATION requires ACCOUNTADMIN."
    exit 1
}
Write-Host "    [OK] Role $ADMIN_ROLE is accessible"

$rules = Invoke-SnowSql "USE ROLE $ROLE; SHOW NETWORK RULES LIKE '$RULE_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $rules -or $rules.Count -eq 0) {
    Write-Host "ERROR: Network rule $RULE_NAME does not exist. Run step_03 first."
    exit 1
}
Write-Host "    [OK] Network rule $RULE_NAME exists"

$secrets = Invoke-SnowSql "USE ROLE $ROLE; SHOW SECRETS LIKE '$SECRET_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $secrets -or $secrets.Count -eq 0) {
    Write-Host "ERROR: Secret $SECRET_NAME does not exist. Run step_04 first."
    exit 1
}
Write-Host "    [OK] Secret $SECRET_NAME exists"

Write-Host "`n==> Creating external access integration $EAI_NAME (as $ADMIN_ROLE)..."
Invoke-SnowSqlDisplay "USE ROLE $ADMIN_ROLE; CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION $EAI_NAME ALLOWED_NETWORK_RULES = ($DB.$SCHEMA.$RULE_NAME) ALLOWED_AUTHENTICATION_SECRETS = ($DB.$SCHEMA.$SECRET_NAME) ENABLED = TRUE;"

Write-Host "`n==> Granting USAGE on $EAI_NAME to $ROLE..."
Invoke-SnowSqlDisplay "USE ROLE $ADMIN_ROLE; GRANT USAGE ON INTEGRATION $EAI_NAME TO ROLE $ROLE;"

if ($SERVICE_ROLE -ne $ROLE) {
    Write-Host "`n==> Granting USAGE on $EAI_NAME to $SERVICE_ROLE..."
    Invoke-SnowSqlDisplay "USE ROLE $ADMIN_ROLE; GRANT USAGE ON INTEGRATION $EAI_NAME TO ROLE $SERVICE_ROLE;"
}

Write-Host "`n==========================================================================="
Write-Host " STEP 5 COMPLETE - External access integration $EAI_NAME created"
Write-Host "==========================================================================="

exit 0
