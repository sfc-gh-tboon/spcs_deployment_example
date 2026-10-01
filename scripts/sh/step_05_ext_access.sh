#!/usr/bin/env bash
# STEP 5 - Create External Access Integration
# NOTE: Requires ACCOUNTADMIN (or CREATE INTEGRATION privilege)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 5 - Create External Access Integration"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ADMIN_ROLE") || {
    echo "ERROR: Cannot switch to role $ADMIN_ROLE."
    echo "       CREATE EXTERNAL ACCESS INTEGRATION requires ACCOUNTADMIN."
    exit 1
}
echo "    [OK] Role $ADMIN_ROLE is accessible"

rules=$(invoke_snow_sql "USE ROLE $ROLE; SHOW NETWORK RULES LIKE '$RULE_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$rules" ]] || ! echo "$rules" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Network rule $RULE_NAME does not exist. Run step_03 first."
    exit 1
fi
echo "    [OK] Network rule $RULE_NAME exists"

secrets=$(invoke_snow_sql "USE ROLE $ROLE; SHOW SECRETS LIKE '$SECRET_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$secrets" ]] || ! echo "$secrets" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Secret $SECRET_NAME does not exist. Run step_04 first."
    exit 1
fi
echo "    [OK] Secret $SECRET_NAME exists"

echo ""
echo "==> Creating external access integration $EAI_NAME (as $ADMIN_ROLE)..."
invoke_snow_sql_display "USE ROLE $ADMIN_ROLE; CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION $EAI_NAME ALLOWED_NETWORK_RULES = ($DB.$SCHEMA.$RULE_NAME) ALLOWED_AUTHENTICATION_SECRETS = ($DB.$SCHEMA.$SECRET_NAME) ENABLED = TRUE;"

echo ""
echo "==> Granting USAGE on $EAI_NAME to $ROLE..."
invoke_snow_sql_display "USE ROLE $ADMIN_ROLE; GRANT USAGE ON INTEGRATION $EAI_NAME TO ROLE $ROLE;"

if [[ "$SERVICE_ROLE" != "$ROLE" ]]; then
    echo ""
    echo "==> Granting USAGE on $EAI_NAME to $SERVICE_ROLE..."
    invoke_snow_sql_display "USE ROLE $ADMIN_ROLE; GRANT USAGE ON INTEGRATION $EAI_NAME TO ROLE $SERVICE_ROLE;"
fi

echo ""
echo "==========================================================================="
echo " STEP 5 COMPLETE - External access integration $EAI_NAME created"
echo "==========================================================================="

exit 0
