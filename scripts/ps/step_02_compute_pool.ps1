# STEP 2 - Create Compute Pool
. "$PSScriptRoot\config.ps1"

Write-Host "`n==========================================================================="
Write-Host " STEP 2 - Create Compute Pool"
Write-Host "==========================================================================="

Write-Host "`n==> Pre-flight checks..."

$result = Invoke-SnowSql "USE ROLE $ROLE"
if (-not $result) { Write-Host "ERROR: Cannot switch to role $ROLE."; exit 1 }
Write-Host "    [OK] Role $ROLE is accessible"

Write-Host "`n==> Creating compute pool $POOL_NAME..."
Write-Host "    Instance: CPU_X64_XS (2 vCPU, 8 GB), Nodes: 1, Auto-suspend: 300s"
Invoke-SnowSqlDisplay "USE ROLE $ROLE; CREATE COMPUTE POOL IF NOT EXISTS $POOL_NAME MIN_NODES = 1 MAX_NODES = 1 INSTANCE_FAMILY = CPU_X64_XS AUTO_RESUME = TRUE AUTO_SUSPEND_SECS = 300;"

Write-Host "`n==> Waiting for compute pool to become ACTIVE (up to 5 minutes)..."
$maxAttempts = 20
for ($i = 1; $i -le $maxAttempts; $i++) {
    $pool = Invoke-SnowSql "DESCRIBE COMPUTE POOL $POOL_NAME"
    $state = if ($pool) { $pool[0].state } else { "UNKNOWN" }
    if ($state -eq "SUSPENDED") {
        Write-Host "    Pool is SUSPENDED. Resuming..."
        Invoke-SnowSqlDisplay "USE ROLE $ROLE; ALTER COMPUTE POOL $POOL_NAME RESUME;"
        Start-Sleep -Seconds 5
        continue
    }
    Write-Host "    Attempt $i/$maxAttempts`: state = $state"
    if ($state -in "ACTIVE", "IDLE") {
        if ($SERVICE_ROLE -ne $ROLE) {
            Write-Host "`n==> Granting USAGE on $POOL_NAME to $SERVICE_ROLE..."
            Invoke-SnowSqlDisplay "USE ROLE $ROLE; GRANT USAGE ON COMPUTE POOL $POOL_NAME TO ROLE $SERVICE_ROLE;"
        }
        Write-Host "`n==========================================================================="
        Write-Host " STEP 2 COMPLETE - Compute pool $POOL_NAME is $state"
        Write-Host "==========================================================================="
        exit 0
    }
    Start-Sleep -Seconds 15
}
Write-Host "ERROR: Compute pool did not reach ACTIVE state within 5 minutes."
exit 1
