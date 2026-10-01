#!/usr/bin/env bash
# STEP 6 - Build Docker Image
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "==========================================================================="
echo " STEP 6 - Build Docker Image"
echo "==========================================================================="

echo ""
echo "==> Pre-flight checks..."

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed or not on PATH."
    exit 1
fi
docker version >/dev/null 2>&1 || { echo "ERROR: Docker is not running. Start Docker Desktop first."; exit 1; }
echo "    [OK] Docker is available"

if ! command -v snow &>/dev/null; then
    echo "ERROR: Snowflake CLI (snow) is not installed."
    echo "       Install: pip install snowflake-cli"
    exit 1
fi
echo "    [OK] Snowflake CLI is available"

repos=$(invoke_snow_sql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA") || true
if [[ -z "$repos" ]] || ! echo "$repos" | jq -e 'length > 0' &>/dev/null; then
    echo "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
fi
repo_url=$(echo "$repos" | jq -r '.[0].repository_url')
echo "    [OK] Image repository exists: $repo_url"

full_image="$repo_url/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "    Full image path: $full_image"

echo ""
echo "==> Building image (platform: linux/amd64)..."
echo "    This may take a few minutes on first run."
echo "    Build context: $PROJECT_ROOT"
run_logged_command "docker buildx build --platform linux/amd64 --tag $full_image $PROJECT_ROOT" \
    docker buildx build --platform linux/amd64 --tag "$full_image" "$PROJECT_ROOT"
if [[ $? -ne 0 ]]; then echo "ERROR: Docker build failed."; exit 1; fi

echo ""
echo "==========================================================================="
echo " STEP 6 COMPLETE - Image built: $full_image"
echo " Run step_07_push_image.sh to push to Snowflake registry."
echo "==========================================================================="

exit 0
