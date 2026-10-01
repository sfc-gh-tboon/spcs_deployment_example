# STEP 9 - Create Service Function
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 9 - Create Service Function"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA"
if (-not $result) { Write-Host "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1 }
Write-Host "    [OK] Role and schema accessible"

Write-Host "`n==> Waiting for service $SERVICE_OBJ to become READY (up to 3 minutes)..."
$maxAttempts = 18
for ($i = 1; $i -le $maxAttempts; $i++) {
    $status = Invoke-SnowSql "USE ROLE $SERVICE_ROLE; SELECT PARSE_JSON(SYSTEM`$GET_SERVICE_STATUS('$DB.$SCHEMA.$SERVICE_OBJ'))[0]['status']::STRING AS status"
    $svcStatus = if ($status) { $status[0].STATUS } else { "UNKNOWN" }
    Write-Host "    Attempt $i/$maxAttempts`: status = $svcStatus"
    if ($svcStatus -eq "READY") { break }
    if ($i -eq $maxAttempts) {
        Write-Host "ERROR: Service did not reach READY state within 3 minutes."
        Write-Host "       Check: CALL SYSTEM`$GET_SERVICE_LOGS('$DB.$SCHEMA.$SERVICE_OBJ', '0', '$CONTAINER_NAME', 100);"
        exit 1
    }
    Start-Sleep -Seconds 10
}

Write-Host "    [OK] Service is READY"

if ($SERVICE_ROLE -ne $ROLE) {
    Write-Host "`n==> Granting BIND SERVICE ENDPOINT on $SERVICE_OBJ to $ROLE..."
    Invoke-SnowSqlDisplay "USE ROLE $SERVICE_ROLE; GRANT BIND SERVICE ENDPOINT ON SERVICE $DB.$SCHEMA.$SERVICE_OBJ TO ROLE $ROLE;"
}

Write-Host "`n==> Creating service function $FUNCTION_NAME..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE OR REPLACE FUNCTION $FUNCTION_NAME(REQUEST VARIANT) RETURNS VARIANT SERVICE = $DB.$SCHEMA.$SERVICE_OBJ ENDPOINT = '$ENDPOINT_NAME' AS '/$ENDPOINT_NAME';"

Write-Host "`n==> Granting USAGE on function to $SERVICE_ROLE..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; GRANT USAGE ON FUNCTION $DB.$SCHEMA.${FUNCTION_NAME}(VARIANT) TO ROLE $SERVICE_ROLE;"

Write-Host "`n==========================================================================="
Write-Host " STEP 9 COMPLETE - Function ${FUNCTION_NAME}(VARIANT) created"
Write-Host " Usage: SELECT ${FUNCTION_NAME}(PARSE_JSON('{`"key`": `"value`"}'));"
Write-Host "==========================================================================="

exit 0
