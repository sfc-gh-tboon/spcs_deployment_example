#!/usr/bin/env bash
# =============================================================================
# Test deployment of the writeback service against the OREGON connection
# =============================================================================
# This script sets up the prerequisites (role + grants) and then runs the
# full deployment. Safe to re-run -- uses IF NOT EXISTS / OR REPLACE.
#
# Usage:
#   bash scripts/sh/test_oregon_deploy.sh
# =============================================================================

set -euo pipefail

CONNECTION="OREGON"
SERVICE_NAME="writeback"
DB="ADMIN_DB"
SCHEMA_NAME="PUBLIC"
ROLE="SYSADMIN"
ADMIN_ROLE="SYSADMIN"
SERVICE_ROLE="WRITEBACK_ROLE"
WRITEBACK_DB="ADMIN_DB"
WRITEBACK_SCHEMA="PUBLIC"
WRITEBACK_WH="COMPUTE_WH"

echo "==========================================================================="
echo " Test Deployment: OREGON connection"
echo "==========================================================================="
echo ""

# --- Step 0: Create the service role and grant prerequisites ---
echo "==> Creating service role $SERVICE_ROLE (if not exists)..."
snow sql --connection "$CONNECTION" --query "
  USE ROLE $ADMIN_ROLE;
  CREATE ROLE IF NOT EXISTS $SERVICE_ROLE;
  GRANT ROLE $SERVICE_ROLE TO ROLE $ROLE;
"

echo "==> Granting prerequisites to $SERVICE_ROLE..."
snow sql --connection "$CONNECTION" --query "
  USE ROLE $ROLE;
  GRANT USAGE ON DATABASE $DB TO ROLE $SERVICE_ROLE;
  GRANT USAGE ON SCHEMA $DB.$SCHEMA_NAME TO ROLE $SERVICE_ROLE;
  GRANT CREATE SERVICE ON SCHEMA $DB.$SCHEMA_NAME TO ROLE $SERVICE_ROLE;
  GRANT USAGE ON WAREHOUSE $WRITEBACK_WH TO ROLE $SERVICE_ROLE;
"

echo ""
echo "==> Running full deployment..."
echo ""

# --- Run the deployment ---
export SNOWFLAKE_CONNECTION="$CONNECTION"
export SERVICE_NAME
export DB
export SCHEMA="$SCHEMA_NAME"
export ROLE
export ADMIN_ROLE
export SERVICE_ROLE
export IMAGE_TAG="latest"
export TARGET_HOSTS="postman-echo.com"
export WRITEBACK_DB_NAME="$WRITEBACK_DB"
export WRITEBACK_SCHEMA_NAME="$WRITEBACK_SCHEMA"
export WRITEBACK_WAREHOUSE="$WRITEBACK_WH"
export DEBUG_MODE="true"
export API_SECRET="dummy-token-for-testing"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/sh/deploy_all.sh"
