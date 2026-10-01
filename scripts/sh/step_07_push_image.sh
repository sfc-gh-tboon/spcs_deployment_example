#!/usr/bin/env bash
# STEP 7 - Push Docker Image to Snowflake Registry
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 7 - Push Docker Image to Snowflake Registry"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed or not on PATH."
    exit 1
fi
echo "    [OK] Docker is available"

repos=$(invoke_snow_sql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$repos" ]] || ! echo "$repos" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
fi
repo_url=$(echo "$repos" | jq -r '.[0].repository_url')
full_image="$repo_url/${IMAGE_NAME}:${IMAGE_TAG}"

# Check the image exists locally
if ! docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -qF "$full_image"; then
    echo "WARNING: Image $full_image not found locally. Run step_06 first."
    echo "         Attempting push anyway (it may exist in Docker cache)."
fi
echo "    [OK] Image path: $full_image"

echo ""
echo "==> Logging in to Snowflake image registry..."
echo "    (A browser window may open for SSO authentication)"
run_logged_command "snow spcs image-registry login --connection $SNOWFLAKE_CONNECTION" \
    snow spcs image-registry login --connection "$SNOWFLAKE_CONNECTION" 2>/dev/null
if [[ $? -ne 0 ]]; then echo "ERROR: Failed to log in to registry."; exit 1; fi

echo ""
echo "==> Pushing image to Snowflake registry..."
run_logged_command "docker push $full_image" docker push "$full_image"
if [[ $? -ne 0 ]]; then echo "ERROR: Docker push failed."; exit 1; fi

echo ""
echo "==========================================================================="
echo " STEP 7 COMPLETE - Image pushed: $full_image"
echo "==========================================================================="

exit 0
