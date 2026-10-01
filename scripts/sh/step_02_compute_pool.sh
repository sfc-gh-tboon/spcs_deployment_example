#!/usr/bin/env bash
# STEP 2 - Create Compute Pool
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 2 - Create Compute Pool"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

result=$(invoke_snow_sql "USE ROLE $ROLE") || { echo "ERROR: Cannot switch to role $ROLE."; exit 1; }
echo "    [OK] Role $ROLE is accessible"

echo ""
echo "==> Creating compute pool $POOL_NAME..."
echo "    Instance: CPU_X64_XS (2 vCPU, 8 GB), Nodes: 1, Auto-suspend: 300s"
invoke_snow_sql_display "USE ROLE $ROLE; CREATE COMPUTE POOL IF NOT EXISTS $POOL_NAME MIN_NODES = 1 MAX_NODES = 1 INSTANCE_FAMILY = CPU_X64_XS AUTO_RESUME = TRUE AUTO_SUSPEND_SECS = 300;"

echo ""
echo "==> Waiting for compute pool to become ACTIVE (up to 5 minutes)..."
max_attempts=20
for ((i=1; i<=max_attempts; i++)); do
    pool=$(invoke_snow_sql "DESCRIBE COMPUTE POOL $POOL_NAME") || true
    state="UNKNOWN"
    if [[ -n "$pool" ]]; then
        state=$(echo "$pool" | jq -r '.[0].state // "UNKNOWN"')
    fi

    if [[ "$state" == "SUSPENDED" ]]; then
        echo "    Pool is SUSPENDED. Resuming..."
        invoke_snow_sql_display "USE ROLE $ROLE; ALTER COMPUTE POOL $POOL_NAME RESUME;"
        sleep 5
        continue
    fi

    echo "    Attempt $i/$max_attempts: state = $state"
    if [[ "$state" == "ACTIVE" || "$state" == "IDLE" ]]; then
        if [[ "$SERVICE_ROLE" != "$ROLE" ]]; then
            echo ""
            echo "==> Granting USAGE on $POOL_NAME to $SERVICE_ROLE..."
            invoke_snow_sql_display "USE ROLE $ROLE; GRANT USAGE ON COMPUTE POOL $POOL_NAME TO ROLE $SERVICE_ROLE;"
        fi
        echo ""
        echo "==========================================================================="
        echo " STEP 2 COMPLETE - Compute pool $POOL_NAME is $state"
        echo "==========================================================================="
        exit 0
    fi
    sleep 15
done

echo "ERROR: Compute pool did not reach ACTIVE state within 5 minutes."
exit 1
