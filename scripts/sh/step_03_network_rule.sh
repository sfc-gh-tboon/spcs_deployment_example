#!/usr/bin/env bash
# STEP 3 - Create Network Rule
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 3 - Create Network Rule"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA") || { echo "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1; }
echo "    [OK] Role and schema accessible"

echo ""
echo "==> Creating network rule $RULE_NAME..."
# Convert comma-separated hosts to SQL VALUE_LIST format: ('host1', 'host2')
host_list=$(echo "$TARGET_HOSTS" | tr ',' '\n' | sed "s/^[[:space:]]*/'/;s/[[:space:]]*$/'/" | paste -sd ',' -)
echo "    Allowed egress hosts: $TARGET_HOSTS"
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE OR REPLACE NETWORK RULE $RULE_NAME MODE = EGRESS TYPE = HOST_PORT VALUE_LIST = ($host_list);"

echo ""
echo "==========================================================================="
echo " STEP 3 COMPLETE - Network rule $RULE_NAME created"
echo "==========================================================================="

exit 0
