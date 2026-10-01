# STEP 6 - Build Docker Image
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 6 - Build Docker Image"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker is not installed or not on PATH."
    exit 1
}
docker version >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker is not running. Start Docker Desktop first."
    exit 1
}
Write-Host "    [OK] Docker is available"

if (-not (Get-Command snow -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Snowflake CLI (snow) is not installed."
    Write-Host "       Install: winget install Snowflake.SnowflakeCLI"
    exit 1
}
Write-Host "    [OK] Snowflake CLI is available"

$repos = Invoke-SnowSql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $repos -or $repos.Count -eq 0) {
    Write-Host "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
}
$repoUrl = $repos[0].repository_url
Write-Host "    [OK] Image repository exists: $repoUrl"

$fullImage = "$repoUrl/${IMAGE_NAME}:${IMAGE_TAG}"
Write-Host "`n    Full image path: $fullImage"

$projectRoot = (Resolve-Path "$PSScriptRoot\..\..").Path

Write-Host "`n==> Building image (platform: linux/amd64)..."
Write-Host "    This may take a few minutes on first run."
Write-Host "    Build context: $projectRoot"
Invoke-LoggedCommand "docker buildx build --platform linux/amd64 --tag $fullImage $projectRoot" { docker buildx build --platform linux/amd64 --tag $fullImage $projectRoot }
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Docker build failed."; exit 1 }

Write-Host "`n==========================================================================="
Write-Host " STEP 6 COMPLETE - Image built: $fullImage"
Write-Host " Run step_07_push_image.ps1 to push to Snowflake registry."
Write-Host "==========================================================================="

exit 0
