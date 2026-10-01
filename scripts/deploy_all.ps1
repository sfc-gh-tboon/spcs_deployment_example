# =============================================================================
# DEPLOY ALL - Run all deployment steps in order
# =============================================================================
# Usage:
#   .\scripts\deploy_all.ps1
#
# To skip prompts, set environment variables:
#   $env:SNOWFLAKE_CONNECTION = "myconn"
#   $env:DB = "ADMIN_DB"
#   ... etc.
# =============================================================================

# Load config up front (prompts once for all values)
. "$PSScriptRoot\config.ps1"

# Export all config values as environment variables so child step scripts
# (launched via & operator) find them without re-prompting.
$env:SNOWFLAKE_CONNECTION = $SNOWFLAKE_CONNECTION
$env:SERVICE_NAME         = $SERVICE_NAME
$env:DB                   = $DB
$env:SCHEMA               = $SCHEMA
$env:ROLE                 = $ROLE
$env:ADMIN_ROLE           = $ADMIN_ROLE
$env:IMAGE_TAG            = $IMAGE_TAG
$env:TARGET_HOSTS         = $TARGET_HOSTS
$env:SERVICE_ROLE         = $SERVICE_ROLE

# API_SECRET is prompted by step_04 separately from config.ps1.
# Pre-prompt here so it's exported for the child process.
if (-not $env:API_SECRET) {
    $tokenInput = Read-Host "API bearer token [dummy-token-for-testing]"
    $env:API_SECRET = if ($tokenInput) { $tokenInput } else { "dummy-token-for-testing" }
}

Write-Host "`n==========================================================================="
Write-Host " SPCS API Proxy - Full Deployment ($SERVICE_NAME)"
Write-Host "==========================================================================="
Write-Host ""
Write-Host " Configuration:"
Write-Host "   Service:    $SERVICE_NAME (objects: ${SERVICE_OBJ}, ${POOL_NAME}, ...)"
Write-Host "   Connection: $SNOWFLAKE_CONNECTION"
Write-Host "   Database:   $DB.$SCHEMA"
Write-Host "   Role:       $ROLE  (admin: $ADMIN_ROLE)"
Write-Host "   Image tag:  $IMAGE_TAG"
Write-Host ""
Write-Host " Steps: image repo > compute pool > network rule > secret > EAI >"
Write-Host "        docker build > docker push > service > function > test"
Write-Host ""

$steps = @(
    @{ Script = "step_01_image_repo.ps1";    Name = "Image Repository" }
    @{ Script = "step_02_compute_pool.ps1";  Name = "Compute Pool" }
    @{ Script = "step_03_network_rule.ps1";  Name = "Network Rule" }
    @{ Script = "step_04_secret.ps1";        Name = "Secret" }
    @{ Script = "step_05_ext_access.ps1";    Name = "External Access Integration" }
    @{ Script = "step_06_build_image.ps1";   Name = "Docker Image Build" }
    @{ Script = "step_07_push_image.ps1";    Name = "Docker Image Push" }
    @{ Script = "step_08_service.ps1";       Name = "SPCS Service" }
    @{ Script = "step_09_function.ps1";      Name = "Service Function" }
    @{ Script = "step_10_test.ps1";          Name = "Test" }
)

foreach ($step in $steps) {
    & "$PSScriptRoot\$($step.Script)"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nDEPLOYMENT FAILED at $($step.Name) (exit code $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n==========================================================================="
Write-Host " DEPLOYMENT COMPLETE - All 10 steps passed" -ForegroundColor Green
Write-Host "==========================================================================="
Write-Host ""
Write-Host " The service is live. Use it from SQL:"
Write-Host "   SELECT ${FUNCTION_NAME}(PARSE_JSON('{""key"": ""value""}'));"
Write-Host ""
Write-Host " To stop billing:"
Write-Host "   ALTER SERVICE $DB.$SCHEMA.$SERVICE_OBJ SUSPEND;"
Write-Host "   ALTER COMPUTE POOL $POOL_NAME SUSPEND;"
Write-Host ""
