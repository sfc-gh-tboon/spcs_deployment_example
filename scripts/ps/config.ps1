# =============================================================================
# Shared Configuration for SPCS Deployment Scripts
# =============================================================================
# Values come from: environment variable > interactive prompt > default.
#
# To skip prompts, set environment variables before running:
#   $env:SNOWFLAKE_CONNECTION = "default"
#   $env:SERVICE_NAME = "my_service"
#   $env:DB = "ADMIN_DB"
#   $env:SCHEMA = "PUBLIC"
#   $env:ROLE = "SYSADMIN"
#   $env:ADMIN_ROLE = "ACCOUNTADMIN"
#   $env:SERVICE_ROLE = "MY_SERVICE_ROLE"  (role the service runs as)
#   $env:TARGET_HOSTS = "api.example.com,api2.example.com"  (allowed egress hosts)
#   $env:IMAGE_TAG = "latest"
#   $env:WRITEBACK_DB_NAME = "MY_DB"       (database the writeback procedures live in)
#   $env:WRITEBACK_SCHEMA_NAME = "MY_SCHEMA"  (schema the writeback procedures live in)
#   $env:WRITEBACK_WAREHOUSE = "MY_WH"     (warehouse for writeback procedure calls)
# =============================================================================

function Get-Config {
    param([string]$EnvVar, [string]$Prompt, [string]$Default)
    $val = [Environment]::GetEnvironmentVariable($EnvVar)
    if (-not $val) { $val = $script:ConfigCache[$EnvVar] }
    if (-not $val) {
        $userInput = Read-Host "$Prompt [$Default]"
        $val = if ($userInput) { $userInput } else { $Default }
    }
    $script:ConfigCache[$EnvVar] = $val
    return $val
}

if (-not $script:ConfigCache) { $script:ConfigCache = @{} }

# --- Snowflake connection (asked first, validated before continuing) ---
$SNOWFLAKE_CONNECTION = Get-Config "SNOWFLAKE_CONNECTION" "Snowflake CLI connection name" "default"

# Ensure snow CLI is on PATH (refresh from registry if needed)
if (-not (Get-Command snow -ErrorAction SilentlyContinue)) {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command snow -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Snowflake CLI (snow) not found. Install: winget install Snowflake.SnowflakeCLI"
        exit 1
    }
}

# Test the connection - let the user retry if it fails
while ($true) {
    $prevPref = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $testOut = snow sql --connection $SNOWFLAKE_CONNECTION --query "SELECT 1 AS connected" --format csv 2>&1
    $testExit = $LASTEXITCODE; $ErrorActionPreference = $prevPref
    $testText = ($testOut | Where-Object { $_ -is [string] } | Out-String).Trim()
    if ($testText -match "connected" -or $testText -match "^1$") {
        Write-Host "    [OK] Connection '$SNOWFLAKE_CONNECTION' is valid"
        break
    }
    Write-Host "ERROR: Connection '$SNOWFLAKE_CONNECTION' failed." -ForegroundColor Red
    Write-Host "       Available connections:"
    $ErrorActionPreference = "Continue"
    snow connection list 2>$null
    $ErrorActionPreference = $prevPref
    $retry = Read-Host "`nEnter a valid connection name (or Ctrl+C to quit)"
    if ($retry) { $SNOWFLAKE_CONNECTION = $retry; $script:ConfigCache["SNOWFLAKE_CONNECTION"] = $retry }
}

# --- Remaining configuration ---
$SERVICE_NAME         = Get-Config "SERVICE_NAME" "Service name (used for all object names)" "my_service"
if ($SERVICE_NAME -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    Write-Host "ERROR: SERVICE_NAME must contain only letters, digits, and underscores (no hyphens or spaces)."
    exit 1
}
$DB                   = Get-Config "DB" "Database name" "ADMIN_DB"
$SCHEMA               = Get-Config "SCHEMA" "Schema name" "PUBLIC"
$ROLE                 = Get-Config "ROLE" "Deployment role" "SYSADMIN"
$ADMIN_ROLE           = Get-Config "ADMIN_ROLE" "Admin role for integrations" "ACCOUNTADMIN"
$IMAGE_TAG            = Get-Config "IMAGE_TAG" "Docker image tag" "latest"
$TARGET_HOSTS         = Get-Config "TARGET_HOSTS" "Allowed egress hosts (comma-separated)" "postman-echo.com"

# SERVICE_ROLE: the least-privilege role the service runs as.
# Default is derived from SERVICE_NAME (e.g., my_service -> MY_SERVICE_ROLE).
$defaultServiceRole = $SERVICE_NAME.ToUpper() + "_ROLE"
$SERVICE_ROLE         = Get-Config "SERVICE_ROLE" "Service role (the role the SPCS service runs as)" $defaultServiceRole

# Derived object names (from SERVICE_NAME)
$SVC_UPPER     = $SERVICE_NAME.ToUpper()
$REPO_NAME     = "${SVC_UPPER}_REPO"
$IMAGE_NAME    = "${SERVICE_NAME}_service".ToLower()
$POOL_NAME     = "${SVC_UPPER}_COMPUTE_POOL"
$RULE_NAME     = "${SVC_UPPER}_API_RULE"
$SECRET_NAME   = "${SVC_UPPER}_API_TOKEN"
$EAI_NAME      = "${SVC_UPPER}_API_ACCESS_INTEGRATION"
$SERVICE_OBJ    = "${SVC_UPPER}_SERVICE"
$CONTAINER_NAME = ($SERVICE_NAME.ToLower()) -replace '_', '-'
$ENDPOINT_NAME  = "route"
$FUNCTION_NAME  = "ROUTE_${SVC_UPPER}_WRITEBACK"

# Writeback target configuration (the database/schema/warehouse the procedures live in)
$WRITEBACK_DB_NAME     = Get-Config "WRITEBACK_DB_NAME" "Writeback target database" $DB
$WRITEBACK_SCHEMA_NAME = Get-Config "WRITEBACK_SCHEMA_NAME" "Writeback target schema" $SCHEMA
$WRITEBACK_WAREHOUSE   = Get-Config "WRITEBACK_WAREHOUSE" "Writeback warehouse" "WH_XS"

# Debug mode (set to "true" to enable verbose logging in the container)
$DEBUG_MODE            = Get-Config "DEBUG_MODE" "Enable debug logging in the service (true/false)" "false"

# --- Logging ---
$LOG_DIR = Join-Path $PSScriptRoot "..\..\logs"
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }
if (-not $script:LOG_FILE) {
    $script:LOG_FILE = Join-Path $LOG_DIR "deploy_${SERVICE_NAME}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}
$LOG_FILE = $script:LOG_FILE
Write-Host "    Log file: $LOG_FILE"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Message" | Add-Content -Path $LOG_FILE
}

# Log all config values (mask the secret)
Write-Log "=== Configuration ==="
Write-Log "SERVICE_NAME=$SERVICE_NAME"
Write-Log "SNOWFLAKE_CONNECTION=$SNOWFLAKE_CONNECTION"
Write-Log "DB=$DB  SCHEMA=$SCHEMA"
Write-Log "ROLE=$ROLE  ADMIN_ROLE=$ADMIN_ROLE  SERVICE_ROLE=$SERVICE_ROLE"
Write-Log "TARGET_HOSTS=$TARGET_HOSTS"
Write-Log "IMAGE_TAG=$IMAGE_TAG"
Write-Log "WRITEBACK_DB=$WRITEBACK_DB_NAME  WRITEBACK_SCHEMA=$WRITEBACK_SCHEMA_NAME  WRITEBACK_WH=$WRITEBACK_WAREHOUSE"
Write-Log "DEBUG_MODE=$DEBUG_MODE"
Write-Log "Derived: REPO=$REPO_NAME  POOL=$POOL_NAME  SERVICE=$SERVICE_OBJ  CONTAINER=$CONTAINER_NAME  ENDPOINT=$ENDPOINT_NAME  FUNCTION=$FUNCTION_NAME"

# --- Pre-flight: check tools are available ---
if (-not (Get-Command snow -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Snowflake CLI (snow) is not on PATH."
    Write-Host "       Install: winget install Snowflake.SnowflakeCLI"
    exit 1
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: Docker is not on PATH. Steps 06/07 (build/push) will fail."
}

# Helper: run snow sql and return parsed JSON, suppressing warnings
function Invoke-SnowSql {
    param([string]$Query, [string]$Format = "json")
    $logQuery = $Query -replace "SECRET_STRING\s*=\s*'[^']*'", "SECRET_STRING = '****'"
    Write-Log "SQL: $logQuery"
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $allOutput = snow sql --connection $SNOWFLAKE_CONNECTION --query $Query --format $Format 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevPref
    $stdout = $allOutput | Where-Object { $_ -is [string] }
    $stderr = $allOutput | Where-Object { $_ -isnot [string] }
    if ($exitCode -ne 0) {
        $errText = ($stderr | Out-String)
        if ($errText -match "Error|error|SQL compilation") {
            Write-Log "SQL ERROR (exit=$exitCode): $($errText.Trim())"
            return $null
        }
    }
    $text = if ($stdout) { ($stdout | Out-String).Trim() } else { ($stderr | ForEach-Object { $_.ToString() } | Out-String).Trim() }
    $lines = $text -split "`n" | Where-Object {
        $_ -notmatch "UserWarning|warnings\.warn|encoding_diagnostics"
    }
    $text = ($lines -join "`n").Trim()
    if (-not $text) { Write-Log "SQL RESULT: (empty)"; return $null }
    Write-Log "SQL OK (exit=$exitCode)"
    if ($Format -eq "json") {
        try { return $text | ConvertFrom-Json }
        catch { return $null }
    }
    return $text
}

# Helper: run snow sql for display (shows table output)
function Invoke-SnowSqlDisplay {
    param([string]$Query)
    $logQuery = $Query -replace "SECRET_STRING\s*=\s*'[^']*'", "SECRET_STRING = '****'"
    Write-Log "SQL: $logQuery"
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    snow sql --connection $SNOWFLAKE_CONNECTION --query $Query 2>$null
    $code = $LASTEXITCODE
    Write-Log "SQL DISPLAY (exit=$code)"
    $ErrorActionPreference = $prevPref
    return $code
}

# Helper: run a command and log it
function Invoke-LoggedCommand {
    param([string]$Description, [scriptblock]$Command)
    Write-Log "CMD: $Description"
    & $Command
    $code = $LASTEXITCODE
    Write-Log "CMD RESULT: exit=$code"
    return $code
}
