# STEP 3 - Create Network Rule
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 3 - Create Network Rule"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA"
if (-not $result) { Write-Host "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1 }
Write-Host "    [OK] Role and schema accessible"

Write-Host "`n==> Creating network rule $RULE_NAME..."
# Convert comma-separated hosts to SQL VALUE_LIST format: ('host1', 'host2')
$hostList = ($TARGET_HOSTS -split ',' | ForEach-Object { "'$($_.Trim())'" }) -join ', '
Write-Host "    Allowed egress hosts: $TARGET_HOSTS"
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE OR REPLACE NETWORK RULE $RULE_NAME MODE = EGRESS TYPE = HOST_PORT VALUE_LIST = ($hostList);"

Write-Host "`n==========================================================================="
Write-Host " STEP 3 COMPLETE - Network rule $RULE_NAME created"
Write-Host "==========================================================================="

exit 0
