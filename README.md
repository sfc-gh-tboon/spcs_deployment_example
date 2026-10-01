# SPCS API Proxy Service

A reusable template for deploying an external API proxy as a
[**Snowpark Container Services (SPCS)**](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview)
service, callable from SQL via a
[service function](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services#service-functions).

Provide a service name (e.g., `pricing`, `weather`, `fraud`) and the scripts
create all Snowflake objects automatically with consistent naming.

---

## Why SPCS instead of a Python UDF?

| | Python UDF | SPCS Service (this repo) |
|---|---|---|
| Cold start | 2-8 s (Conda env setup) | ~0 ms (container already running) |
| HTTP connection pooling | Per-sandbox, not guaranteed | True persistent pool per worker |
| Latency (warm) | ~300-600 ms | ~50-150 ms |
| Token rotation | Requires UDF recreation | `ALTER SECRET` + container restart |
| Debugging | Event table only | Container logs via `SYSTEM$GET_SERVICE_LOGS` |

---

## Architecture

```
SQL caller  (using SERVICE_ROLE or any granted role)
    |  SELECT FETCH_<NAME>_RESPONSE(PARSE_JSON('{...}'))
    v
Service Function  (SQL -> HTTP bridge, owned by ROLE, granted to SERVICE_ROLE)
    |  POST /proxy  {"data": [[0, {...}]]}
    v
Flask container  (running as SERVICE_ROLE in SPCS compute pool)
    |  POST to TARGET_URL (configurable via env var)
    v
Target API  (external - allowed hosts defined by TARGET_HOSTS)
```

---

## Naming Convention

When you enter a service name (e.g., `pricing`), all objects are derived:

| Object | Name |
|---|---|
| Image repository | `PRICING_REPO` |
| [Compute pool](https://docs.snowflake.com/en/sql-reference/sql/create-compute-pool) | `PRICING_COMPUTE_POOL` |
| [Network rule](https://docs.snowflake.com/en/sql-reference/sql/create-network-rule) | `PRICING_API_RULE` |
| [Secret](https://docs.snowflake.com/en/sql-reference/sql/create-secret) | `PRICING_API_TOKEN` |
| [External access integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration) | `PRICING_API_ACCESS_INTEGRATION` |
| [SPCS service](https://docs.snowflake.com/en/sql-reference/sql/create-service) | `PRICING_SERVICE` |
| [SQL function](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services#service-functions) | `FETCH_PRICING_RESPONSE(VARIANT)` |

---

## Role Model

The scripts use three roles with clear separation of concerns:

| Role | Config variable | Used for |
|---|---|---|
| Deployment role | `ROLE` (default: `SYSADMIN`) | Creates infrastructure: image repo, compute pool, network rule, secret, function |
| Admin role | `ADMIN_ROLE` (default: `ACCOUNTADMIN`) | Creates [external access integration](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration) (requires CREATE INTEGRATION privilege) |
| Service role | `SERVICE_ROLE` (default: `<NAME>_ROLE`) | The SPCS service runs as this role. Must already exist with the required grants |

The service role is **not created** by these scripts -- it must exist beforehand.
The service role needs these **prerequisite grants** (set up before deployment):

```sql
-- Prerequisites: grant these BEFORE running the deployment scripts
GRANT USAGE ON DATABASE <DB> TO ROLE <SERVICE_ROLE>;
GRANT USAGE ON SCHEMA <DB>.<SCHEMA> TO ROLE <SERVICE_ROLE>;
GRANT CREATE SERVICE ON SCHEMA <DB>.<SCHEMA> TO ROLE <SERVICE_ROLE>;
```

The deployment scripts automatically grant the rest:

```sql
-- Granted by step_01:
GRANT READ ON IMAGE REPOSITORY <DB>.<SCHEMA>.<NAME>_REPO TO ROLE <SERVICE_ROLE>;
-- Granted by step_02:
GRANT USAGE ON COMPUTE POOL <NAME>_COMPUTE_POOL TO ROLE <SERVICE_ROLE>;
-- Granted by step_04:
GRANT READ ON SECRET <DB>.<SCHEMA>.<NAME>_API_TOKEN TO ROLE <SERVICE_ROLE>;
-- Granted by step_05:
GRANT USAGE ON INTEGRATION <NAME>_API_ACCESS_INTEGRATION TO ROLE <SERVICE_ROLE>;
-- Granted by step_09 (BIND goes to ROLE so it can create the function on the service):
GRANT BIND SERVICE ENDPOINT ON SERVICE <DB>.<SCHEMA>.<NAME>_SERVICE TO ROLE <ROLE>;
GRANT USAGE ON FUNCTION <DB>.<SCHEMA>.FETCH_<NAME>_RESPONSE(VARIANT) TO ROLE <SERVICE_ROLE>;
```

---

## Project Structure

```
spcs_deployment_example/
├── app/
│   ├── main.py                  Flask proxy service (generic)
│   └── requirements.txt         Python dependencies
├── scripts/
│   ├── config.ps1               Shared config - prompts, logging, helpers
│   ├── deploy_all.ps1           Full deployment orchestrator (10 steps)
│   ├── cleanup.ps1              Teardown all objects
│   ├── step_01_image_repo.ps1   Create image repository
│   ├── step_02_compute_pool.ps1 Create compute pool + wait for ACTIVE
│   ├── step_03_network_rule.ps1 Create network egress rule (uses TARGET_HOSTS)
│   ├── step_04_secret.ps1       Create secret (API token)
│   ├── step_05_ext_access.ps1   Create external access integration
│   ├── step_06_build_image.ps1  Build Docker image (linux/amd64)
│   ├── step_07_push_image.ps1   Push image to Snowflake registry
│   ├── step_08_service.ps1      Create SPCS service (runs as SERVICE_ROLE)
│   ├── step_09_function.ps1     Create SQL function + grant to SERVICE_ROLE
│   └── step_10_test.ps1         Run connectivity + batch tests
├── Dockerfile                   Container build definition
├── logs/                        Deployment logs (git-ignored)
├── service_spec.template.yaml   Service spec template (edit this for customization)
├── service.yaml                 Generated by step_08 (resolved, for troubleshooting)
├── .gitignore
└── README.md                    This file
```

---

## Prerequisites

1. **Docker Desktop** with buildx support
2. **Snowflake CLI** (`snow`):
   - Windows: `winget install Snowflake.SnowflakeCLI`
   - macOS/Linux: `pip install snowflake-cli` or see [Snowflake CLI docs](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation)
3. **Snowflake account** with:
   - `SYSADMIN` role (or equivalent for creating objects)
   - `ACCOUNTADMIN` role (for creating the external access integration)
   - A **service role** that the SPCS service will run as (see Role Model above)
   - SPCS enabled on your account
4. **API bearer token** (or use the dummy value for testing)

---

## Quick Start

Run from the **project root directory**:

```powershell
cd path/to/spcs_deployment_example
.\scripts\deploy_all.ps1
```

Individual steps can also be run standalone:

```powershell
.\scripts\step_03_network_rule.ps1
```

The scripts validate the Snowflake connection first, then prompt for configuration:

```
Snowflake CLI connection name [default]: myconn
==> Testing connection 'myconn'...
    [OK] Connection 'myconn' is valid
Service name (used for all object names) [my_service]: pricing
Database name [ADMIN_DB]:
Schema name [PUBLIC]:
Deployment role [SYSADMIN]:
Admin role for integrations [ACCOUNTADMIN]:
Docker image tag [latest]:
Allowed egress hosts (comma-separated) [postman-echo.com]: api.example.com
Service role (the role the SPCS service runs as) [PRICING_ROLE]:
API bearer token [dummy-token-for-testing]:
```

If a connection name is invalid, the scripts show available connections and
let you retry.

### Skip prompts with environment variables

Set any of these before running to skip the corresponding prompt:

| Variable | Default | Description |
|---|---|---|
| `SNOWFLAKE_CONNECTION` | `default` | Snowflake CLI connection name (validated on start) |
| `SERVICE_NAME` | `my_service` | Base name for all Snowflake objects (letters, digits, underscores only) |
| `DB` | `ADMIN_DB` | Database where objects are created |
| `SCHEMA` | `PUBLIC` | Schema where objects are created |
| `ROLE` | `SYSADMIN` | Deployment role -- creates infrastructure objects |
| `ADMIN_ROLE` | `ACCOUNTADMIN` | Admin role -- creates external access integration |
| `IMAGE_TAG` | `latest` | Docker image tag pushed to Snowflake registry |
| `TARGET_HOSTS` | `postman-echo.com` | Comma-separated hosts the container can reach (network rule) |
| `SERVICE_ROLE` | `<NAME>_ROLE` | Pre-existing role the SPCS service runs as |
| `API_SECRET` | `dummy-token-for-testing` | API bearer token stored as a Snowflake secret |

```powershell
$env:SNOWFLAKE_CONNECTION = "myconn"
$env:SERVICE_NAME = "pricing"
$env:TARGET_HOSTS = "api.example.com"
$env:SERVICE_ROLE = "PRICING_ROLE"
$env:API_SECRET = "your-real-token"
.\scripts\deploy_all.ps1
```

---

## What Each Step Does

| Step | What it does | Role used | Idempotent? |
|------|-------------|-----------|-------------|
| 1 | Create image repository | `$ROLE` | IF NOT EXISTS (skips) |
| 2 | Create compute pool, wait for ACTIVE | `$ROLE` | IF NOT EXISTS (skips) |
| 3 | Create network rule (from TARGET_HOSTS) | `$ROLE` | OR REPLACE (updates) |
| 4 | Create secret | `$ROLE` | IF NOT EXISTS (skips) |
| 5 | Create external access integration | `$ADMIN_ROLE` | OR REPLACE (updates) |
| 6 | Build Docker image (linux/amd64) | -- | Rebuilds layers |
| 7 | Push image to Snowflake registry | -- | Overwrites tag |
| 8 | Create SPCS service, generate service.yaml | `$SERVICE_ROLE` | IF NOT EXISTS (skips) |
| 9 | Wait for READY, create function, grant to SERVICE_ROLE | `$ROLE` | OR REPLACE (updates) |
| 10 | Run connectivity + batch tests | `$ROLE` | Read-only |

All steps are safe to re-run. Objects using `IF NOT EXISTS` are skipped if they
already exist; objects using `OR REPLACE` are updated with the latest config.

Note: Step 8 uses `IF NOT EXISTS`, so re-running won't update a running service.
To update the service spec (e.g., new image tag), drop it first or use
`ALTER SERVICE ... FROM SPECIFICATION`.

Each step can be run independently: `.\scripts\step_03_network_rule.ps1`

---

## Customizing the Service Spec (step_08)

The [service specification](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference)
is defined in `service_spec.template.yaml`. Step 08 reads it, substitutes
placeholders with your config values, and passes the resolved spec to
`CREATE SERVICE`. The resolved spec is also saved to `service.yaml` for reference.

To customize, edit `service_spec.template.yaml` directly -- no need to touch
the PowerShell scripts. Available placeholders:

| Placeholder | Replaced with |
|---|---|
| `{{IMAGE}}` | Full image path (registry/db/schema/repo/image:tag) |
| `{{DB}}` | Database name |
| `{{SCHEMA}}` | Schema name |
| `{{SECRET_NAME}}` | Secret object name (e.g. `PRICING_API_TOKEN`) |
| `{{ENDPOINT_NAME}}` | Endpoint name and Flask route path (default: `proxy`) |
| `{{CONTAINER_NAME}}` | Container name (derived from service name, e.g. `pricing`) |

Here are the values you're most likely to change:

### Container environment variables

The container reads these env vars at startup (defined in `app/main.py`):

| Env var | Set in spec | Default | Description |
|---|---|---|---|
| `TARGET_URL` | Yes | `https://postman-echo.com/post` | The external API URL the proxy calls. **Change this to your real API endpoint.** |
| `REQUEST_TIMEOUT_S` | Yes | `30` | Per-request timeout in seconds. Must be less than the Gunicorn `--timeout` (60s in Dockerfile). If you increase this beyond 60, also increase the Gunicorn timeout. |
| `API_TOKEN` | Via secret | *(required)* | Bearer token injected from the Snowflake secret |
| `API_HEADER_KEY` | No (optional) | *(empty)* | Extra header value (e.g. `ocp-apim-subscription-key` for Azure APIM) |

To change `TARGET_URL`, edit `service_spec.template.yaml`:

```yaml
env:
  TARGET_URL: "https://your-api.example.com/v1/predict"   # <-- change this
  REQUEST_TIMEOUT_S: "30"
```

To add `API_HEADER_KEY`, add it under `env:` in the template:

```yaml
env:
  TARGET_URL: "https://your-api.example.com/v1/predict"
  REQUEST_TIMEOUT_S: "30"
  API_HEADER_KEY: "your-subscription-key"                  # <-- add this
```

### Resource limits

The default spec requests 0.5 CPU / 512 Mi memory with limits of 1 CPU / 1 Gi.
Adjust based on your API call volume:

```yaml
resources:
  requests:
    cpu: "0.5"        # minimum guaranteed CPU
    memory: 512Mi     # minimum guaranteed memory
  limits:
    cpu: "1"          # maximum CPU
    memory: 1Gi       # maximum memory (container is killed if exceeded)
```

### Readiness probe

The container exposes `GET /` as a health check. SPCS polls this before
routing traffic. The defaults work for most cases:

```yaml
readinessProbe:
  port: 8080
  path: /
```

### Endpoint visibility

The endpoint is `public: false` by default, meaning it's only accessible via
service functions (SQL). Set to `true` if you need direct HTTP access via an
ingress URL:

```yaml
endpoints:
  - name: proxy              # matches ENDPOINT_NAME in config.ps1
    port: 8080
    public: true     # generates an ingress URL accessible outside Snowflake
```

### Container name vs endpoint name

The spec uses two separate names:

- **`CONTAINER_NAME`** -- the container name in the spec (derived from `SERVICE_NAME`,
  e.g. `pricing`). Used by `SYSTEM$GET_SERVICE_LOGS` to identify the container.
- **`ENDPOINT_NAME`** -- the endpoint name in the spec (default: `proxy`). Used by
  step 09 in `CREATE FUNCTION ... ENDPOINT = '<name>' AS '/<name>'`.

If you change `ENDPOINT_NAME`, the Flask route in `app/main.py` must match. For
example, if you set `ENDPOINT_NAME = "predict"`, update the route:

```python
@app.post("/predict")     # must match ENDPOINT_NAME
def proxy_request():
```

### Full generated spec (example)

After running step 08 with `SERVICE_NAME=pricing`, the generated `service.yaml`
looks like:

```yaml
spec:
  containers:
    - name: pricing
      image: <account>.registry.snowflakecomputing.com/<db>/<schema>/pricing_repo/pricing_service:latest
      env:
        TARGET_URL: "https://postman-echo.com/post"
        REQUEST_TIMEOUT_S: "30"
      secrets:
        - snowflakeSecret:
            objectName: ADMIN_DB.PUBLIC.PRICING_API_TOKEN
          envVarName: API_TOKEN
      resources:
        requests:
          cpu: "0.5"
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
      readinessProbe:
        port: 8080
        path: /
  endpoints:
    - name: proxy
      port: 8080
      public: false
```

### Updating a running service

Step 08 uses `CREATE SERVICE IF NOT EXISTS`, so re-running it won't update an
existing service. To apply spec changes to a running service:

```sql
ALTER SERVICE ADMIN_DB.PUBLIC.PRICING_SERVICE
  FROM SPECIFICATION $$ <paste updated spec here> $$;
```

Or drop and recreate:

```powershell
# Drop the service first (step 08 uses IF NOT EXISTS, so it won't update in-place)
# Replace the values with your actual config
snow sql --connection $env:SNOWFLAKE_CONNECTION --query "USE ROLE $env:SERVICE_ROLE; DROP SERVICE IF EXISTS $env:DB.$env:SCHEMA.${env:SERVICE_NAME}_SERVICE;"
# Then re-run step 08
.\scripts\step_08_service.ps1
```

See [ALTER SERVICE](https://docs.snowflake.com/en/sql-reference/sql/alter-service) for more options.

---

## Monitoring and Debugging

```sql
-- Container logs (third argument is the container name, not the endpoint)
CALL SYSTEM$GET_SERVICE_LOGS('ADMIN_DB.PUBLIC.PRICING_SERVICE', '0', 'pricing', 100);

-- Service health
CALL SYSTEM$GET_SERVICE_STATUS('ADMIN_DB.PUBLIC.PRICING_SERVICE');

-- Compute pool status
DESCRIBE COMPUTE POOL PRICING_COMPUTE_POOL;
```

See [Working with services](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services)
for full monitoring options including event tables and metrics.

The resolved `service.yaml` in the project root (generated by step 08) shows
the exact spec passed to CREATE SERVICE -- useful for comparing against what's
actually running.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `ERROR: Docker is not running` | Docker Desktop not started | Start Docker Desktop, wait for it to be ready |
| `ERROR: Connection '...' failed` | Wrong connection name or expired credentials | Run `snow connection list` to see valid names; re-authenticate if needed |
| `Pool did not reach ACTIVE within 5 minutes` | Compute pool slow to provision | Re-run step 02; it will detect the pool and resume waiting |
| `Service not READY within 3 minutes` | Container crash or bad image | Check logs: `CALL SYSTEM$GET_SERVICE_LOGS(...)` (see Monitoring above) |
| `Insufficient privileges` on CREATE SERVICE | SERVICE_ROLE missing grants | Run the [prerequisite grants](#role-model) listed in the Role Model section |
| Step fails but `deploy_all` continues | Stale `$LASTEXITCODE` | Re-run the individual step script to see the actual error |
| `ERROR: SERVICE_NAME must contain only letters...` | Hyphens or spaces in name | Use only `A-Z`, `a-z`, `0-9`, `_` (e.g. `my_service`, not `my-service`) |
| Docker build fails with `no matching manifest for linux/amd64` | Base image doesn't support amd64 | Ensure Docker buildx is installed: `docker buildx version` |
| Service stuck in `SUSPENDED` on re-run | Compute pool auto-suspended | Steps 02 and 08 auto-resume suspended pools; just re-run |

For any other issue, check the deployment log file at `logs/deploy_<service>_<timestamp>.log`
-- it contains every SQL command and exit code.

---

## Cleanup

```powershell
.\scripts\cleanup.ps1
```

Prompts for the service name and connection, confirms with YES, then drops all
objects in reverse dependency order. The service role is **not dropped** (it's
assumed to be managed separately).

---

## Logging

Every SQL command, Docker operation, and exit code is automatically logged to
`logs/deploy_<service>_<timestamp>.log`. The log file path is printed at the
start of each run.

Logs include:
- Full configuration block (service name, connection, roles, derived names)
- Every SQL statement with timestamp (secret values are masked)
- Exit codes and error messages
- Docker build/push commands

Share the log file when asking for help -- it has everything needed to diagnose
the issue without needing to reproduce it.

---

## Snowflake Documentation

| Concept | Link |
|---|---|
| Snowpark Container Services overview | [SPCS overview](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview) |
| Service specification reference | [Spec reference](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference) |
| Service functions (SQL to HTTP) | [Service functions](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services#service-functions) |
| CREATE SERVICE | [CREATE SERVICE](https://docs.snowflake.com/en/sql-reference/sql/create-service) |
| CREATE COMPUTE POOL | [CREATE COMPUTE POOL](https://docs.snowflake.com/en/sql-reference/sql/create-compute-pool) |
| CREATE NETWORK RULE | [CREATE NETWORK RULE](https://docs.snowflake.com/en/sql-reference/sql/create-network-rule) |
| CREATE SECRET | [CREATE SECRET](https://docs.snowflake.com/en/sql-reference/sql/create-secret) |
| External Access Integration | [CREATE EXTERNAL ACCESS INTEGRATION](https://docs.snowflake.com/en/sql-reference/sql/create-external-access-integration) |
| Image repositories | [Image registry and repository](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-registry-repository) |
| Monitoring services | [Working with services](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/working-with-services) |
| Snowflake CLI | [Snowflake CLI installation](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation) |
