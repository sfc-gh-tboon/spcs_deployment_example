# STEP 7 - Push Docker Image to Snowflake Registry
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 7 - Push Docker Image to Snowflake Registry"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Docker is not installed or not on PATH."
    exit 1
}
Write-Host "    [OK] Docker is available"

$repos = Invoke-SnowSql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $repos -or $repos.Count -eq 0) {
    Write-Host "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
}
$repoUrl = $repos[0].repository_url
$fullImage = "$repoUrl/${IMAGE_NAME}:${IMAGE_TAG}"

# Check the image exists locally
$localImages = docker images --format "{{.Repository}}:{{.Tag}}" 2>$null
if ($localImages -notcontains $fullImage) {
    Write-Host "WARNING: Image $fullImage not found locally. Run step_06 first."
    Write-Host "         Attempting push anyway (it may exist in Docker cache)."
}
Write-Host "    [OK] Image path: $fullImage"

Write-Host "`n==> Logging in to Snowflake image registry..."
Write-Host "    (A browser window may open for SSO authentication)"
Invoke-LoggedCommand "snow spcs image-registry login --connection $SNOWFLAKE_CONNECTION" { snow spcs image-registry login --connection $SNOWFLAKE_CONNECTION 2>$null }
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to log in to registry."; exit 1 }

Write-Host "`n==> Pushing image to Snowflake registry..."
Invoke-LoggedCommand "docker push $fullImage" { docker push $fullImage }
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Docker push failed."; exit 1 }

Write-Host "`n==========================================================================="
Write-Host " STEP 7 COMPLETE - Image pushed: $fullImage"
Write-Host "==========================================================================="

exit 0
