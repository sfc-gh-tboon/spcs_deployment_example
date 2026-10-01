#!/usr/bin/env bash
# STEP 8 - Create SPCS Service
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 8 - Create SPCS Service"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA") || { echo "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1; }
echo "    [OK] Role and schema accessible"

pool=$(invoke_snow_sql "DESCRIBE COMPUTE POOL $POOL_NAME") || true
state="UNKNOWN"
if [[ -n "$pool" ]]; then
    state=$(echo "$pool" | jq -r '.[0].state // "UNKNOWN"')
fi

if [[ "$state" == "SUSPENDED" ]]; then
    echo "    Compute pool is SUSPENDED. Resuming..."
    invoke_snow_sql_display "USE ROLE $ROLE; ALTER COMPUTE POOL $POOL_NAME RESUME;"
    sleep 10
    pool=$(invoke_snow_sql "DESCRIBE COMPUTE POOL $POOL_NAME") || true
    state=$(echo "$pool" | jq -r '.[0].state // "UNKNOWN"')
fi

if [[ "$state" == "ACTIVE" || "$state" == "IDLE" || "$state" == "STARTING" ]]; then
    echo "    [OK] Compute pool $POOL_NAME is $state"
else
    echo "ERROR: Compute pool $POOL_NAME is $state. Run step_02 first."
    exit 1
fi

repos=$(invoke_snow_sql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$repos" ]] || ! echo "$repos" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
fi
repo_url=$(echo "$repos" | jq -r '.[0].repository_url')
full_image="$repo_url/${IMAGE_NAME}:${IMAGE_TAG}"
echo "    [OK] Image path: $full_image"

# --- Generate service.yaml from template ---
template_path="$PROJECT_ROOT/service_spec.template.yaml"
if [[ ! -f "$template_path" ]]; then
    echo "ERROR: Template not found at $template_path"
    echo "       Expected: service_spec.template.yaml in project root."
    exit 1
fi

echo ""
echo "==> Reading service spec template..."
write_log "Reading template: $template_path"

# Read template, strip comment lines, substitute placeholders
spec=$(grep -v '^\s*#' "$template_path")
spec="${spec//\{\{IMAGE\}\}/$full_image}"
spec="${spec//\{\{DB\}\}/$DB}"
spec="${spec//\{\{SCHEMA\}\}/$SCHEMA}"
spec="${spec//\{\{CONTAINER_NAME\}\}/$CONTAINER_NAME}"
spec="${spec//\{\{ENDPOINT_NAME\}\}/$ENDPOINT_NAME}"
spec="${spec//\{\{WRITEBACK_DB_NAME\}\}/$WRITEBACK_DB_NAME}"
spec="${spec//\{\{WRITEBACK_SCHEMA_NAME\}\}/$WRITEBACK_SCHEMA_NAME}"
spec="${spec//\{\{WRITEBACK_WAREHOUSE\}\}/$WRITEBACK_WAREHOUSE}"
spec="${spec//\{\{DEBUG_MODE\}\}/$DEBUG_MODE}"

yaml_path="$PROJECT_ROOT/service.yaml"
echo "$spec" > "$yaml_path"
echo "    Resolved spec saved to: $yaml_path"

echo ""
echo "==> Creating service $SERVICE_OBJ (as role $SERVICE_ROLE)..."
invoke_snow_sql_display "USE ROLE $SERVICE_ROLE; USE SCHEMA $DB.$SCHEMA; CREATE SERVICE IF NOT EXISTS $SERVICE_OBJ IN COMPUTE POOL $POOL_NAME EXTERNAL_ACCESS_INTEGRATIONS = ($EAI_NAME) FROM SPECIFICATION \$\$${spec}\$\$;"

echo ""
echo "==> Checking initial status..."
invoke_snow_sql_display "CALL SYSTEM\$GET_SERVICE_STATUS('$DB.$SCHEMA.$SERVICE_OBJ')"

echo ""
echo "==========================================================================="
echo " STEP 8 COMPLETE - Service $SERVICE_OBJ created"
echo " Service spec saved to: service.yaml (for troubleshooting)"
echo " Service may take 1-3 minutes to become READY"
echo "==========================================================================="

exit 0
