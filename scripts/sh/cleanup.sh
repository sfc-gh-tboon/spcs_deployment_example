#!/usr/bin/env bash
# =============================================================================
# CLEANUP - Drop all SPCS objects created by the deployment scripts
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " SPCS Writeback Service - Cleanup ($SERVICE_NAME)"
echo "==========================================================================="
echo ""
echo " This will PERMANENTLY DROP the following objects:"
echo "   - Service function:  $DB.$SCHEMA.$FUNCTION_NAME"
echo "   - SPCS service:      $DB.$SCHEMA.$SERVICE_OBJ"
echo "   - Compute pool:      $POOL_NAME"
echo "   - External access:   $EAI_NAME"
echo "   - Secret:            $DB.$SCHEMA.$SECRET_NAME"
echo "   - Network rule:      $DB.$SCHEMA.$RULE_NAME"
echo "   - Image repository:  $DB.$SCHEMA.$REPO_NAME (includes all pushed images)"
echo ""

read -rp "Are you sure? Type YES to confirm: " confirm
if [[ "$confirm" != "YES" ]]; then
    echo "Cancelled. No objects were dropped."
    exit 0
fi

echo ""

invoke_drop() {
    local label="$1"
    local query="$2"
    echo "==> $label..."
    if invoke_snow_sql "$query" >/dev/null 2>&1; then
        echo "    Done."
    else
        echo -e "    ${YELLOW}WARNING: May have failed. Verify manually.${NC}"
    fi
}

invoke_drop "Dropping service function" "USE ROLE $ROLE; DROP FUNCTION IF EXISTS $DB.$SCHEMA.${FUNCTION_NAME}(VARIANT)"

echo "==> Suspending and dropping service (as $SERVICE_ROLE)..."
invoke_snow_sql "USE ROLE $SERVICE_ROLE; ALTER SERVICE IF EXISTS $DB.$SCHEMA.$SERVICE_OBJ SUSPEND" >/dev/null 2>&1 || true
invoke_drop "Dropping service" "USE ROLE $SERVICE_ROLE; DROP SERVICE IF EXISTS $DB.$SCHEMA.$SERVICE_OBJ"

echo "==> Suspending compute pool..."
invoke_snow_sql "USE ROLE $ROLE; ALTER COMPUTE POOL IF EXISTS $POOL_NAME SUSPEND" >/dev/null 2>&1 || true
invoke_drop "Dropping compute pool" "USE ROLE $ROLE; DROP COMPUTE POOL IF EXISTS $POOL_NAME"

invoke_drop "Dropping external access integration (as $ADMIN_ROLE)" "USE ROLE $ADMIN_ROLE; DROP EXTERNAL ACCESS INTEGRATION IF EXISTS $EAI_NAME"
invoke_drop "Dropping secret" "USE ROLE $ROLE; DROP SECRET IF EXISTS $DB.$SCHEMA.$SECRET_NAME"
invoke_drop "Dropping network rule" "USE ROLE $ROLE; DROP NETWORK RULE IF EXISTS $DB.$SCHEMA.$RULE_NAME"
invoke_drop "Dropping image repository (and all images)" "USE ROLE $ROLE; DROP IMAGE REPOSITORY IF EXISTS $DB.$SCHEMA.$REPO_NAME"

echo ""
echo "==========================================================================="
echo " CLEANUP COMPLETE - All objects dropped"
echo "==========================================================================="

exit 0
