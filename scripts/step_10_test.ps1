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

Write-Host "`n==> Test 1: Missing productCode (should return FAILURE with 'Unrecognized productCode')..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT $FUNCTION_NAME(PARSE_JSON('{`"transactionId`": `"test-001`"}')) AS result;"

Write-Host "`n==> Test 2: Valid productCode (should return ACCEPTED)..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT $FUNCTION_NAME(PARSE_JSON('{`"productCode`": `"FA`", `"submissionSFDCId`": `"SUB-001`", `"transactionId`": `"TXN-001`"}')) AS result;"

Write-Host "`n==> Test 3: Batch test (3 rows with different product codes)..."
Invoke-SnowSqlDisplay "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT id, $FUNCTION_NAME(OBJECT_CONSTRUCT('productCode', code, 'submissionSFDCId', id, 'transactionId', txn)) AS result FROM (SELECT 'FA' AS code, 'SUB-A' AS id, 'TXN-A' AS txn UNION ALL SELECT 'NH', 'SUB-B', 'TXN-B' UNION ALL SELECT 'CI', 'SUB-C', 'TXN-C');"

Write-Host "`n==========================================================================="
Write-Host " STEP 10 COMPLETE"
Write-Host "==========================================================================="
Write-Host ""
Write-Host " Review the output above:"
Write-Host "   Test 1: Should show FAILURE with 'Unrecognized productCode'"
Write-Host "   Test 2: Should show ACCEPTED with procedure USP_WRITEBACK_GROUP1"
Write-Host "   Test 3: Should show 3 ACCEPTED rows (GROUP1, GROUP2, GROUP4)"
Write-Host ""

exit 0
