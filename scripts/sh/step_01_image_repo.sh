#!/usr/bin/env bash
# STEP 1 - Create Image Repository
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 1 - Create Image Repository"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA") || { echo "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1; }
echo "    [OK] Role $ROLE and schema $DB.$SCHEMA accessible"

echo ""
echo "==> Creating image repository $REPO_NAME..."
invoke_snow_sql_display "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA; CREATE IMAGE REPOSITORY IF NOT EXISTS $REPO_NAME;"

echo ""
echo "==> Repository URL:"
repos=$(invoke_snow_sql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -n "$repos" ]]; then
    repo_url=$(echo "$repos" | jq -r '.[0].repository_url // empty')
    echo "    $repo_url"
else
    echo "WARNING: Could not parse repository URL."
fi

if [[ "$SERVICE_ROLE" != "$ROLE" ]]; then
    echo ""
    echo "==> Granting READ on $REPO_NAME to $SERVICE_ROLE..."
    invoke_snow_sql_display "USE ROLE $ROLE; GRANT READ ON IMAGE REPOSITORY $DB.$SCHEMA.$REPO_NAME TO ROLE $SERVICE_ROLE;"
fi

echo ""
echo "==========================================================================="
echo " STEP 1 COMPLETE - Image repository ready"
echo "==========================================================================="

exit 0
