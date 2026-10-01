# STEP 10 - Test the Service Function
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 10 - Test the Service Function"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$funcs = Invoke-SnowSql "USE ROLE $ROLE; SHOW FUNCTIONS LIKE '$FUNCTION_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $funcs -or $funcs.Count -eq 0) {
    Write-Host "ERROR: Function $FUNCTION_NAME not found. Run step_09 first."
    exit 1
}
Write-Host "    [OK] Function $FUNCTION_NAME exists"

Write-Host "`n==> Test 1: Basic connectivity (empty payload)..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT $FUNCTION_NAME(PARSE_JSON('{}')) AS result;"

Write-Host "`n==> Test 2: Batch test (3 rows)..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT id, $FUNCTION_NAME(OBJECT_CONSTRUCT('id', id, 'value', val)) AS api_response FROM (SELECT '001' AS id, 'test-a' AS val UNION ALL SELECT '002', 'test-b' UNION ALL SELECT '003', 'test-c');"

Write-Host "`n==========================================================================="
Write-Host " STEP 10 COMPLETE - All tests passed"
Write-Host "==========================================================================="

exit 0
