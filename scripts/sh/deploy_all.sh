#!/usr/bin/env bash
# =============================================================================
# DEPLOY ALL - Run all deployment steps in order
# =============================================================================
# Usage:
#   ./scripts/sh/deploy_all.sh
#
# To skip prompts, set environment variables:
#   export SNOWFLAKE_CONNECTION="myconn"
#   export DB="ADMIN_DB"
#   ... etc.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " SPCS Writeback Service - Full Deployment ($SERVICE_NAME)"
echo "==========================================================================="
echo ""
echo " Configuration:"
echo "   Service:    $SERVICE_NAME (objects: ${SERVICE_OBJ}, ${POOL_NAME}, ...)"
echo "   Connection: $SNOWFLAKE_CONNECTION"
echo "   Database:   $DB.$SCHEMA"
echo "   Writeback:  $WRITEBACK_DB_NAME.$WRITEBACK_SCHEMA_NAME (warehouse: $WRITEBACK_WAREHOUSE)"
echo "   Role:       $ROLE  (admin: $ADMIN_ROLE)"
echo "   Debug mode: $DEBUG_MODE"
echo "   Image tag:  $IMAGE_TAG"
echo ""
echo " Steps: image repo > compute pool > network rule > secret > EAI >"
echo "        docker build > docker push > service > function > test"
echo ""

steps=(
    "step_01_image_repo.sh:Image Repository"
    "step_02_compute_pool.sh:Compute Pool"
    "step_03_network_rule.sh:Network Rule"
    "step_04_secret.sh:Secret"
    "step_05_ext_access.sh:External Access Integration"
    "step_06_build_image.sh:Docker Image Build"
    "step_07_push_image.sh:Docker Image Push"
    "step_08_service.sh:SPCS Service"
    "step_09_function.sh:Service Function"
    "step_10_test.sh:Test"
)

for entry in "${steps[@]}"; do
    script="${entry%%:*}"
    name="${entry#*:}"
    bash "$SCRIPT_DIR/$script"
    code=$?
    if [[ $code -ne 0 ]]; then
        echo -e "\n${RED}DEPLOYMENT FAILED at $name (exit code $code)${NC}"
        exit 1
    fi
done

echo ""
echo -e "==========================================================================="
echo -e "${GREEN} DEPLOYMENT COMPLETE - All 10 steps passed${NC}"
echo "==========================================================================="
echo ""
echo " The service is live. Use it from SQL:"
echo "   SELECT ${FUNCTION_NAME}(PARSE_JSON('{\"key\": \"value\"}'));"
echo ""
echo " To stop billing:"
echo "   ALTER SERVICE $DB.$SCHEMA.$SERVICE_OBJ SUSPEND;"
echo "   ALTER COMPUTE POOL $POOL_NAME SUSPEND;"
echo ""
