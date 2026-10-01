#!/usr/bin/env bash
# STEP 9 - Create Service Function
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 9 - Create Service Function"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA") || { echo "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1; }
echo "    [OK] Role and schema accessible"

echo ""
echo "==> Waiting for service $SERVICE_OBJ to become READY (up to 3 minutes)..."
max_attempts=18
for ((i=1; i<=max_attempts; i++)); do
    status_json=$(invoke_snow_sql "USE ROLE $SERVICE_ROLE; SELECT PARSE_JSON(SYSTEM\$GET_SERVICE_STATUS('$DB.$SCHEMA.$SERVICE_OBJ'))[0]['status']::STRING AS status") || true
    svc_status="UNKNOWN"
    if [[ -n "$status_json" ]]; then
        svc_status=$(echo "$status_json" | jq -r '.[0].STATUS // "UNKNOWN"')
    fi
    echo "    Attempt $i/$max_attempts: status = $svc_status"
    if [[ "$svc_status" == "READY" ]]; then
        break
    fi
    if [[ $i -eq $max_attempts ]]; then
        echo "ERROR: Service did not reach READY state within 3 minutes."
        echo "       Check: CALL SYSTEM\$GET_SERVICE_LOGS('$DB.$SCHEMA.$SERVICE_OBJ', '0', '$CONTAINER_NAME', 100);"
        exit 1
    fi
    sleep 10
done

echo "    [OK] Service is READY"

if [[ "$SERVICE_ROLE" != "$ROLE" ]]; then
    echo ""
    echo "==> Granting BIND SERVICE ENDPOINT on $SERVICE_OBJ to $ROLE..."
    invoke_snow_sql_display "USE ROLE $SERVICE_ROLE; GRANT BIND SERVICE ENDPOINT ON SERVICE $DB.$SCHEMA.$SERVICE_OBJ TO ROLE $ROLE;"
fi

echo ""
echo "==> Creating service function $FUNCTION_NAME..."
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE OR REPLACE FUNCTION $FUNCTION_NAME(REQUEST VARIANT) RETURNS VARIANT SERVICE = $DB.$SCHEMA.$SERVICE_OBJ ENDPOINT = '$ENDPOINT_NAME' AS '/$ENDPOINT_NAME';"

echo ""
echo "==> Granting USAGE on function to $SERVICE_ROLE..."
invoke_snow_sql_display "USE ROLE $ROLE; GRANT USAGE ON FUNCTION $DB.$SCHEMA.${FUNCTION_NAME}(VARIANT) TO ROLE $SERVICE_ROLE;"

echo ""
echo "==========================================================================="
echo " STEP 9 COMPLETE - Function ${FUNCTION_NAME}(VARIANT) created"
echo " Usage: SELECT ${FUNCTION_NAME}(PARSE_JSON('{\"key\": \"value\"}'));"
echo "==========================================================================="

exit 0
