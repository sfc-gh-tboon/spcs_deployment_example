# STEP 8 - Create SPCS Service
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 8 - Create SPCS Service"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE; USE SCHEMA $DB.$SCHEMA"
if (-not $result) { Write-Host "ERROR: Cannot access $DB.$SCHEMA as role $ROLE."; exit 1 }
Write-Host "    [OK] Role and schema accessible"

$pool = Invoke-SnowSql "DESCRIBE COMPUTE POOL $POOL_NAME"
$state = if ($pool) { $pool[0].state } else { "UNKNOWN" }
if ($state -eq "SUSPENDED") {
    Write-Host "    Compute pool is SUSPENDED. Resuming..."
    Invoke-SnowSqlDisplay "USE ROLE $ROLE; ALTER COMPUTE POOL $POOL_NAME RESUME;"
    Start-Sleep -Seconds 10
    $pool = Invoke-SnowSql "DESCRIBE COMPUTE POOL $POOL_NAME"
    $state = if ($pool) { $pool[0].state } else { "UNKNOWN" }
}
if ($state -in "ACTIVE", "IDLE", "STARTING") {
    Write-Host "    [OK] Compute pool $POOL_NAME is $state"
} else {
    Write-Host "ERROR: Compute pool $POOL_NAME is $state. Run step_02 first."
    exit 1
}

$repos = Invoke-SnowSql "SHOW IMAGE REPOSITORIES LIKE '$REPO_NAME' IN SCHEMA $DB.$SCHEMA"
if (-not $repos -or $repos.Count -eq 0) {
    Write-Host "ERROR: Image repository $REPO_NAME not found. Run step_01 first."
    exit 1
}
$repoUrl = $repos[0].repository_url
$fullImage = "$repoUrl/${IMAGE_NAME}:${IMAGE_TAG}"
Write-Host "    [OK] Image path: $fullImage"

# --- Generate service.yaml from template ---
$templatePath = Join-Path $PSScriptRoot "..\..\service_spec.template.yaml"
if (-not (Test-Path $templatePath)) {
    Write-Host "ERROR: Template not found at $templatePath"
    Write-Host "       Expected: service_spec.template.yaml in project root."
    exit 1
}
Write-Host "`n==> Reading service spec template..."
Write-Log "Reading template: $templatePath"
$spec = Get-Content -Path $templatePath -Raw

# Strip comment lines (YAML comments break the $$ literal in CREATE SERVICE)
$spec = ($spec -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

# Substitute placeholders (use .Replace() to avoid regex backreference issues with $)
$spec = $spec.Replace('{{IMAGE}}', $fullImage)
$spec = $spec.Replace('{{DB}}', $DB)
$spec = $spec.Replace('{{SCHEMA}}', $SCHEMA)
$spec = $spec.Replace('{{CONTAINER_NAME}}', $CONTAINER_NAME)
$spec = $spec.Replace('{{ENDPOINT_NAME}}', $ENDPOINT_NAME)
$spec = $spec.Replace('{{WRITEBACK_DB_NAME}}', $WRITEBACK_DB_NAME)
$spec = $spec.Replace('{{WRITEBACK_SCHEMA_NAME}}', $WRITEBACK_SCHEMA_NAME)
$spec = $spec.Replace('{{WRITEBACK_WAREHOUSE}}', $WRITEBACK_WAREHOUSE)
$spec = $spec.Replace('{{DEBUG_MODE}}', $DEBUG_MODE)

$yamlPath = Join-Path $PSScriptRoot "..\..\service.yaml"
[System.IO.File]::WriteAllText($yamlPath, $spec)
Write-Host "    Resolved spec saved to: $(Resolve-Path $yamlPath)"

Write-Host "`n==> Creating service $SERVICE_OBJ (as role $SERVICE_ROLE)..."
Invoke-SnowSqlDisplay "USE ROLE $SERVICE_ROLE; USE SCHEMA $DB.$SCHEMA; CREATE SERVICE IF NOT EXISTS $SERVICE_OBJ IN COMPUTE POOL $POOL_NAME EXTERNAL_ACCESS_INTEGRATIONS = ($EAI_NAME) FROM SPECIFICATION `$`$$spec`$`$;"

Write-Host "`n==> Checking initial status..."
Invoke-SnowSqlDisplay "CALL SYSTEM`$GET_SERVICE_STATUS('$DB.$SCHEMA.$SERVICE_OBJ')"

Write-Host "`n==========================================================================="
Write-Host " STEP 8 COMPLETE - Service $SERVICE_OBJ created"
Write-Host " Service spec saved to: service.yaml (for troubleshooting)"
Write-Host " Service may take 1-3 minutes to become READY"
Write-Host "==========================================================================="

exit 0
