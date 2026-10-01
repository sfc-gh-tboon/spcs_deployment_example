#!/usr/bin/env bash
# STEP 4 - Create Secret
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

token_value="${API_SECRET:-}"
if [[ -z "$token_value" ]]; then
    read -rp "External access token (for outbound calls) [dummy-token-for-testing]: " token_value
    token_value="${token_value:-dummy-token-for-testing}"
fi

echo ""
echo "==========================================================================="
echo " STEP 4 - Create Secret"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA") || { echo "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1; }
echo "    [OK] Role and schema accessible"

secrets=$(invoke_snow_sql "SHOW SECRETS LIKE '$SECRET_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -n "$secrets" ]] && echo "$secrets" | jq -e 'length > 0' &>/dev/null; then
    echo "WARNING: Secret $SECRET_NAME already exists. Using IF NOT EXISTS to avoid overwriting."
    echo "         To update: ALTER SECRET $SECRET_NAME SET SECRET_STRING = 'new-value';"
fi

echo ""
echo "==> Creating secret $SECRET_NAME..."
if [[ "$token_value" == "dummy-token-for-testing" ]]; then
    echo "    Using DUMMY token value (set API_SECRET env var for a real token)"
else
    echo "    Using provided token value"
fi

# Escape single quotes for SQL
safe_token="${token_value//\'/\'\'}"
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE SECRET IF NOT EXISTS $SECRET_NAME TYPE = GENERIC_STRING SECRET_STRING = '$safe_token' COMMENT = 'External access token for the $SERVICE_NAME writeback service';"

if [[ "$SERVICE_ROLE" != "$ROLE" ]]; then
    echo ""
    echo "==> Granting READ on $SECRET_NAME to $SERVICE_ROLE..."
    invoke_snow_sql_display "USE ROLE $ROLE; GRANT READ ON SECRET $DB.$SCHEMA.$SECRET_NAME TO ROLE $SERVICE_ROLE;"
fi

echo ""
echo "==========================================================================="
echo " STEP 4 COMPLETE - Secret $SECRET_NAME created"
echo "==========================================================================="

exit 0
