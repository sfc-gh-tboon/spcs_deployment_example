#!/usr/bin/env bash
# STEP 10 - Test the Service Function
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 10 - Test the Service Function"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

funcs=$(invoke_snow_sql "USE ROLE $ROLE; SHOW FUNCTIONS LIKE '$FUNCTION_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$funcs" ]] || ! echo "$funcs" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Function $FUNCTION_NAME not found. Run step_09 first."
    exit 1
fi
echo "    [OK] Function $FUNCTION_NAME exists"

echo ""
echo "==> Test 1: Missing productCode (should return FAILURE with 'Unrecognized productCode')..."
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT $FUNCTION_NAME(PARSE_JSON('{\"transactionId\": \"test-001\"}')) AS result;"

echo ""
echo "==> Test 2: Valid productCode (should return ACCEPTED)..."
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT $FUNCTION_NAME(PARSE_JSON('{\"productCode\": \"FA\", \"submissionSFDCId\": \"SUB-001\", \"transactionId\": \"TXN-001\"}')) AS result;"

echo ""
echo "==> Test 3: Batch test (3 rows with different product codes)..."
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; SELECT id, $FUNCTION_NAME(OBJECT_CONSTRUCT('productCode', code, 'submissionSFDCId', id, 'transactionId', txn)) AS result FROM (SELECT 'FA' AS code, 'SUB-A' AS id, 'TXN-A' AS txn UNION ALL SELECT 'NH', 'SUB-B', 'TXN-B' UNION ALL SELECT 'CI', 'SUB-C', 'TXN-C');"

echo ""
echo "==========================================================================="
echo " STEP 10 COMPLETE"
echo "==========================================================================="
echo ""
echo " Review the output above:"
echo "   Test 1: Should show FAILURE with 'Unrecognized productCode'"
echo "   Test 2: Should show ACCEPTED with procedure USP_WRITEBACK_GROUP1"
echo "   Test 3: Should show 3 ACCEPTED rows (GROUP1, GROUP2, GROUP4)"
echo ""

exit 0
