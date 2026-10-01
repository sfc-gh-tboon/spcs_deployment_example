#!/usr/bin/env bash
# =============================================================================
# Shared Configuration for SPCS Deployment Scripts (Bash)
# =============================================================================
# Values come from: environment variable > interactive prompt > default.
#
# To skip prompts, set environment variables before running:
#   export SNOWFLAKE_CONNECTION="default"
#   export SERVICE_NAME="my_service"
#   export DB="ADMIN_DB"
#   export SCHEMA="PUBLIC"
#   export ROLE="SYSADMIN"
#   export ADMIN_ROLE="ACCOUNTADMIN"
#   export SERVICE_ROLE="MY_SERVICE_ROLE"
#   export TARGET_HOSTS="api.example.com,api2.example.com"
#   export IMAGE_TAG="latest"
#   export WRITEBACK_DB_NAME="MY_DB"
#   export WRITEBACK_SCHEMA_NAME="MY_SCHEMA"
#   export WRITEBACK_WAREHOUSE="MY_WH"
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# get_config: resolve a config value from env var > prompt > default
# ---------------------------------------------------------------------------
get_config() {
    local env_var="$1"
    local prompt="$2"
    local default_val="$3"
    local val="${!env_var:-}"
    if [[ -z "$val" ]]; then
        read -rp "$prompt [$default_val]: " val
        val="${val:-$default_val}"
    fi
    export "$env_var=$val"
    echo "$val"
}

# --- Snowflake connection (asked first, validated before continuing) ---
SNOWFLAKE_CONNECTION=$(get_config "SNOWFLAKE_CONNECTION" "Snowflake CLI connection name" "default")

# Ensure snow CLI is on PATH
if ! command -v snow &>/dev/null; then
    echo "ERROR: Snowflake CLI (snow) not found."
    echo "       Install: pip install snowflake-cli"
    exit 1
fi

# Ensure jq is on PATH
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found. Install: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Test the connection - let the user retry if it fails
while true; do
    test_out=$(snow sql --connection "$SNOWFLAKE_CONNECTION" --query "SELECT 1 AS connected" --format csv 2>&1 || true)
    if echo "$test_out" | grep -qE "connected|^1$"; then
        echo "    [OK] Connection '$SNOWFLAKE_CONNECTION' is valid"
        break
    fi
    echo -e "${RED}ERROR: Connection '$SNOWFLAKE_CONNECTION' failed.${NC}"
    echo "       Available connections:"
    snow connection list 2>/dev/null || true
    read -rp "Enter a valid connection name (or Ctrl+C to quit): " retry
    if [[ -n "$retry" ]]; then
        SNOWFLAKE_CONNECTION="$retry"
        export SNOWFLAKE_CONNECTION
    fi
done

# --- Remaining configuration ---
SERVICE_NAME=$(get_config "SERVICE_NAME" "Service name (used for all object names)" "my_service")
if [[ ! "$SERVICE_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "ERROR: SERVICE_NAME must contain only letters, digits, and underscores (no hyphens or spaces)."
    exit 1
fi
DB=$(get_config "DB" "Database name" "ADMIN_DB")
SCHEMA=$(get_config "SCHEMA" "Schema name" "PUBLIC")
ROLE=$(get_config "ROLE" "Deployment role" "SYSADMIN")
ADMIN_ROLE=$(get_config "ADMIN_ROLE" "Admin role for integrations" "ACCOUNTADMIN")
IMAGE_TAG=$(get_config "IMAGE_TAG" "Docker image tag" "latest")
TARGET_HOSTS=$(get_config "TARGET_HOSTS" "Allowed egress hosts (comma-separated)" "postman-echo.com")

# SERVICE_ROLE: the least-privilege role the service runs as.
DEFAULT_SERVICE_ROLE="$(echo "${SERVICE_NAME}" | tr '[:lower:]' '[:upper:]')_ROLE"
SERVICE_ROLE=$(get_config "SERVICE_ROLE" "Service role (the role the SPCS service runs as)" "$DEFAULT_SERVICE_ROLE")

# Derived object names (from SERVICE_NAME)
SVC_UPPER="$(echo "${SERVICE_NAME}" | tr '[:lower:]' '[:upper:]')"
REPO_NAME="${SVC_UPPER}_REPO"
IMAGE_NAME="$(echo "${SERVICE_NAME}_service" | tr '[:upper:]' '[:lower:]')"
POOL_NAME="${SVC_UPPER}_COMPUTE_POOL"
RULE_NAME="${SVC_UPPER}_API_RULE"
SECRET_NAME="${SVC_UPPER}_API_TOKEN"
EAI_NAME="${SVC_UPPER}_API_ACCESS_INTEGRATION"
SERVICE_OBJ="${SVC_UPPER}_SERVICE"
CONTAINER_NAME="$(echo "${SERVICE_NAME}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
ENDPOINT_NAME="route"
FUNCTION_NAME="ROUTE_${SVC_UPPER}_WRITEBACK"

# Writeback target configuration
WRITEBACK_DB_NAME=$(get_config "WRITEBACK_DB_NAME" "Writeback target database" "$DB")
WRITEBACK_SCHEMA_NAME=$(get_config "WRITEBACK_SCHEMA_NAME" "Writeback target schema" "$SCHEMA")
WRITEBACK_WAREHOUSE=$(get_config "WRITEBACK_WAREHOUSE" "Writeback warehouse" "WH_XS")

# Debug mode
DEBUG_MODE=$(get_config "DEBUG_MODE" "Enable debug logging in the service (true/false)" "false")

# Export all derived names for child scripts
export SNOWFLAKE_CONNECTION SERVICE_NAME DB SCHEMA ROLE ADMIN_ROLE IMAGE_TAG TARGET_HOSTS SERVICE_ROLE
export SVC_UPPER REPO_NAME IMAGE_NAME POOL_NAME RULE_NAME SECRET_NAME EAI_NAME SERVICE_OBJ
export CONTAINER_NAME ENDPOINT_NAME FUNCTION_NAME
export WRITEBACK_DB_NAME WRITEBACK_SCHEMA_NAME WRITEBACK_WAREHOUSE DEBUG_MODE

# --- Logging ---
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE="$LOG_DIR/deploy_${SERVICE_NAME}_$(date +%Y%m%d_%H%M%S).log"
    export LOG_FILE
fi
echo "    Log file: $LOG_FILE"

write_log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] $1" >> "$LOG_FILE"
}

# Log all config values
write_log "=== Configuration ==="
write_log "SERVICE_NAME=$SERVICE_NAME"
write_log "SNOWFLAKE_CONNECTION=$SNOWFLAKE_CONNECTION"
write_log "DB=$DB  SCHEMA=$SCHEMA"
write_log "ROLE=$ROLE  ADMIN_ROLE=$ADMIN_ROLE  SERVICE_ROLE=$SERVICE_ROLE"
write_log "TARGET_HOSTS=$TARGET_HOSTS"
write_log "IMAGE_TAG=$IMAGE_TAG"
write_log "WRITEBACK_DB=$WRITEBACK_DB_NAME  WRITEBACK_SCHEMA=$WRITEBACK_SCHEMA_NAME  WRITEBACK_WH=$WRITEBACK_WAREHOUSE"
write_log "DEBUG_MODE=$DEBUG_MODE"
write_log "Derived: REPO=$REPO_NAME  POOL=$POOL_NAME  SERVICE=$SERVICE_OBJ  CONTAINER=$CONTAINER_NAME  ENDPOINT=$ENDPOINT_NAME  FUNCTION=$FUNCTION_NAME"

# --- Pre-flight: check tools are available ---
if ! command -v snow &>/dev/null; then
    echo "ERROR: Snowflake CLI (snow) is not on PATH."
    echo "       Install: pip install snowflake-cli"
    exit 1
fi
if ! command -v docker &>/dev/null; then
    echo "WARNING: Docker is not on PATH. Steps 06/07 (build/push) will fail."
fi

# ---------------------------------------------------------------------------
# invoke_snow_sql: run snow sql and return JSON, suppressing warnings
# ---------------------------------------------------------------------------
invoke_snow_sql() {
    local query="$1"
    local format="${2:-json}"
    local log_query
    log_query=$(echo "$query" | sed "s/SECRET_STRING[[:space:]]*=[[:space:]]*'[^']*'/SECRET_STRING = '****'/g")
    write_log "SQL: $log_query"

    local output exit_code
    output=$(snow sql --connection "$SNOWFLAKE_CONNECTION" --query "$query" --format "$format" 2>&1) || true
    exit_code=$?

    # Filter warnings
    output=$(echo "$output" | grep -v -E "UserWarning|warnings\.warn|encoding_diagnostics" || true)
    output=$(echo "$output" | sed '/^$/d')

    if [[ -z "$output" ]]; then
        write_log "SQL RESULT: (empty)"
        return 1
    fi

    # Check for errors (match snow CLI error prefixes, not JSON field names like "error_code")
    if echo "$output" | grep -qE "^╭─ Error|SQL compilation error|ERROR:|Error:"; then
        write_log "SQL ERROR (exit=$exit_code): $(echo "$output" | head -5)"
        return 1
    fi

    write_log "SQL OK (exit=$exit_code)"

    # When multiple statements are sent (e.g. "USE ROLE ...; SELECT ..."),
    # snow --format json wraps each result in its own array, producing a
    # nested array like [[{...}], [{...}]].  Callers expect a flat array
    # [{...}], so extract the last result set (the actual query output).
    if echo "$output" | jq -e 'if type == "array" and (.[0] | type) == "array" then true else false end' >/dev/null 2>&1; then
        output=$(echo "$output" | jq '.[-1]')
    fi

    echo "$output"
    return 0
}

# ---------------------------------------------------------------------------
# invoke_snow_sql_display: run snow sql for table display
# ---------------------------------------------------------------------------
invoke_snow_sql_display() {
    local query="$1"
    local log_query
    log_query=$(echo "$query" | sed "s/SECRET_STRING[[:space:]]*=[[:space:]]*'[^']*'/SECRET_STRING = '****'/g")
    write_log "SQL: $log_query"
    snow sql --connection "$SNOWFLAKE_CONNECTION" --query "$query" 2>/dev/null || true
    local code=$?
    write_log "SQL DISPLAY (exit=$code)"
    return $code
}

# ---------------------------------------------------------------------------
# run_logged_command: run a command and log it
# ---------------------------------------------------------------------------
run_logged_command() {
    local description="$1"
    shift
    write_log "CMD: $description"
    "$@"
    local code=$?
    write_log "CMD RESULT: exit=$code"
    return $code
}
