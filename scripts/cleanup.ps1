# =============================================================================
# CLEANUP - Drop all SPCS objects created by the deployment scripts
# =============================================================================
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " SPCS API Proxy - Cleanup ($SERVICE_NAME)"
Write-Host "==========================================================================="
Write-Host ""
Write-Host " This will PERMANENTLY DROP the following objects:"
Write-Host "   - Service function:  $DB.$SCHEMA.$FUNCTION_NAME"
Write-Host "   - SPCS service:      $DB.$SCHEMA.$SERVICE_OBJ"
Write-Host "   - Compute pool:      $POOL_NAME"
Write-Host "   - External access:   $EAI_NAME"
Write-Host "   - Secret:            $DB.$SCHEMA.$SECRET_NAME"
Write-Host "   - Network rule:      $DB.$SCHEMA.$RULE_NAME"
Write-Host "   - Image repository:  $DB.$SCHEMA.$REPO_NAME (includes all pushed images)"
Write-Host ""

$confirm = Read-Host "Are you sure? Type YES to confirm"
if ($confirm -ne "YES") {
    Write-Host "Cancelled. No objects were dropped."
    exit 0
}

Write-Host ""

function Invoke-Drop {
    param([string]$Label, [string]$Query)
    Write-Host "==> $Label..."
    $result = Invoke-SnowSql $Query
    if ($null -eq $result) {
        Write-Host "    WARNING: May have failed. Verify manually." -ForegroundColor Yellow
    } else {
        Write-Host "    Done."
    }
}

Invoke-Drop "Dropping service function" "USE ROLE $ROLE; DROP FUNCTION IF EXISTS $DB.$SCHEMA.${FUNCTION_NAME}(VARIANT)"

Write-Host "==> Suspending and dropping service (as $SERVICE_ROLE)..."
Invoke-SnowSql "USE ROLE $SERVICE_ROLE; ALTER SERVICE IF EXISTS $DB.$SCHEMA.$SERVICE_OBJ SUSPEND" 2>$null | Out-Null
Invoke-Drop "Dropping service" "USE ROLE $SERVICE_ROLE; DROP SERVICE IF EXISTS $DB.$SCHEMA.$SERVICE_OBJ"

Write-Host "==> Suspending compute pool..."
Invoke-SnowSql "USE ROLE $ROLE; ALTER COMPUTE POOL IF EXISTS $POOL_NAME SUSPEND" 2>$null | Out-Null
Invoke-Drop "Dropping compute pool" "USE ROLE $ROLE; DROP COMPUTE POOL IF EXISTS $POOL_NAME"

Invoke-Drop "Dropping external access integration (as $ADMIN_ROLE)" "USE ROLE $ADMIN_ROLE; DROP EXTERNAL ACCESS INTEGRATION IF EXISTS $EAI_NAME"
Invoke-Drop "Dropping secret" "USE ROLE $ROLE; DROP SECRET IF EXISTS $DB.$SCHEMA.$SECRET_NAME"
Invoke-Drop "Dropping network rule" "USE ROLE $ROLE; DROP NETWORK RULE IF EXISTS $DB.$SCHEMA.$RULE_NAME"
Invoke-Drop "Dropping image repository (and all images)" "USE ROLE $ROLE; DROP IMAGE REPOSITORY IF EXISTS $DB.$SCHEMA.$REPO_NAME"

Write-Host "`n==========================================================================="
Write-Host " CLEANUP COMPLETE - All objects dropped"
Write-Host "==========================================================================="

exit 0
