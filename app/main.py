"""
Writeback Route Function
========================
A FastAPI service deployed on Snowpark Container Services (SPCS) that routes
incoming writeback requests to the appropriate Snowflake stored procedure based
on product code.

How it works:
  1. Snowflake executes a service function that POSTs to /route on this container
  2. Each row in the batch contains a JSON payload with a productCode field
  3. The service maps productCode to a stored procedure group (USP_WRITEBACK_GROUP1-4)
  4. The procedure call is dispatched on a background thread so the HTTP response
     returns immediately with an ACCEPTED status
  5. If the productCode is unrecognized the row gets a FAILURE response inline

Endpoints:
  GET  /       Readiness probe (SPCS checks this before routing traffic)
  POST /route  Main routing endpoint; accepts batched SPCS service-function format
"""

import json
import logging
import os
import signal
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import snowflake.connector
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Set DEBUG_MODE=true in the service spec to enable verbose logging. This logs
# full request/response payloads, connection lifecycle events, token refreshes,
# and per-row timing. Leave unset or "false" in production to avoid log bloat.
DEBUG_MODE = os.environ.get("DEBUG_MODE", "false").lower() == "true"

logging.basicConfig(
    level=logging.DEBUG if DEBUG_MODE else logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("writeback_route_fn")

if DEBUG_MODE:
    logger.info("DEBUG_MODE is ON -- verbose logging enabled")

# Maximum request body size in bytes (default 10 MB). Rejects oversized payloads
# before they're fully read into memory.
_MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", str(10 * 1024 * 1024)))

app = FastAPI(title="Writeback Route Function")


@app.middleware("http")
async def _limit_body_size(request: Request, call_next):
    """Reject requests whose Content-Length exceeds the configured cap."""
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > _MAX_BODY_BYTES:
        logger.warning("Request rejected: Content-Length %s exceeds %d byte limit", content_length, _MAX_BODY_BYTES)
        return JSONResponse(
            status_code=413,
            content={"error": f"Request body too large (limit: {_MAX_BODY_BYTES} bytes)"},
        )
    return await call_next(request)

# ---------------------------------------------------------------------------
# Thread pool for background dispatch
# ---------------------------------------------------------------------------
# Bounds concurrent Snowflake connections to avoid exhausting container memory
# or hitting session limits. Workers default to 8 but can be tuned via env var.
_MAX_DISPATCH_WORKERS = int(os.environ.get("MAX_DISPATCH_WORKERS", "8"))
_executor = ThreadPoolExecutor(max_workers=_MAX_DISPATCH_WORKERS, thread_name_prefix="dispatch")
logger.info("Dispatch thread pool started with %d workers", _MAX_DISPATCH_WORKERS)


@app.on_event("shutdown")
def _drain_dispatch_pool():
    """Wait for in-flight dispatches to finish before the process exits."""
    logger.info("Shutdown requested -- draining dispatch thread pool...")
    _executor.shutdown(wait=True, cancel_futures=False)
    logger.info("Dispatch thread pool drained")

# ---------------------------------------------------------------------------
# Product routing table
# ---------------------------------------------------------------------------
# Maps a productCode (uppercased) to the Snowflake stored procedure that
# handles its writeback logic. Update this dictionary to add, remove, or
# reassign product codes to different procedure groups.
PRODUCT_TO_PROCEDURE = {
    "FA": "USP_WRITEBACK_GROUP1",
    "AG": "USP_WRITEBACK_GROUP1",
    "DY": "USP_WRITEBACK_GROUP1",
    "RL": "USP_WRITEBACK_GROUP1",
    "NH": "USP_WRITEBACK_GROUP2",
    "RF": "USP_WRITEBACK_GROUP2",
    "CO": "USP_WRITEBACK_GROUP3",
    "AK": "USP_WRITEBACK_GROUP3",
    "AH": "USP_WRITEBACK_GROUP3",
    "CI": "USP_WRITEBACK_GROUP4",
}

# ---------------------------------------------------------------------------
# Configuration (injected by SPCS at container start)
# ---------------------------------------------------------------------------
# All values are required; the container will crash on startup if any are missing,
# which is the desired behavior so SPCS marks the service as unhealthy immediately.
SNOWFLAKE_HOST = os.environ["SNOWFLAKE_HOST"]
SNOWFLAKE_ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
DB_NAME = os.environ["WRITEBACK_DB_NAME"]
SCHEMA_NAME = os.environ["WRITEBACK_SCHEMA_NAME"]
WAREHOUSE = os.environ["WRITEBACK_WAREHOUSE"]
TOKEN_PATH = "/snowflake/session/token"

logger.info(
    "Configuration loaded: host=%s account=%s db=%s schema=%s warehouse=%s",
    SNOWFLAKE_HOST, SNOWFLAKE_ACCOUNT, DB_NAME, SCHEMA_NAME, WAREHOUSE,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _quote_id(name: str) -> str:
    """Double-quote a Snowflake identifier, escaping any embedded quotes."""
    return '"' + name.replace('"', '""') + '"'


# ---------------------------------------------------------------------------
# OAuth token cache
# ---------------------------------------------------------------------------
# SPCS writes a rotated OAuth token to TOKEN_PATH. We cache the value for up
# to _TOKEN_TTL_S seconds so concurrent background threads share the same read
# instead of each hitting the filesystem. A double-checked lock keeps the
# refresh thread-safe without blocking every caller.
_token_lock = threading.Lock()
_cached_token = None
_token_read_at = 0.0
_TOKEN_TTL_S = 30


def _read_token() -> str:
    """Return the current SPCS OAuth token, reading from disk at most once per TTL window."""
    global _cached_token, _token_read_at
    now = time.monotonic()
    if _cached_token is not None and (now - _token_read_at) < _TOKEN_TTL_S:
        return _cached_token
    with _token_lock:
        if _cached_token is not None and (now - _token_read_at) < _TOKEN_TTL_S:
            return _cached_token
        with open(TOKEN_PATH, "r") as f:
            _cached_token = f.read().strip()
        _token_read_at = time.monotonic()
        logger.debug("OAuth token refreshed from %s (length=%d)", TOKEN_PATH, len(_cached_token))
        return _cached_token


# ---------------------------------------------------------------------------
# Snowflake connection
# ---------------------------------------------------------------------------


def _open_connection():
    """Open a fresh Snowflake connection using the cached OAuth token."""
    logger.debug("Opening Snowflake connection to %s (db=%s schema=%s)", SNOWFLAKE_HOST, DB_NAME, SCHEMA_NAME)
    conn = snowflake.connector.connect(
        host=SNOWFLAKE_HOST,
        account=SNOWFLAKE_ACCOUNT,
        authenticator="oauth",
        token=_read_token(),
        warehouse=WAREHOUSE,
        database=DB_NAME,
        schema=SCHEMA_NAME,
    )
    logger.debug("Snowflake connection established (session_id=%s)", getattr(conn, 'session_id', 'unknown'))
    return conn


# ---------------------------------------------------------------------------
# Response builders
# ---------------------------------------------------------------------------


def _failure(error: str, payload: dict) -> dict:
    """Build a FAILURE response dict, safely extracting IDs from the payload."""
    payload = payload if isinstance(payload, dict) else {}
    return {
        "status": "FAILURE",
        "error": error,
        "submissionId": payload.get("submissionSFDCId"),
        "transactionId": payload.get("transactionId"),
    }


def _accepted(payload: dict, procedure: str) -> dict:
    """Build an ACCEPTED response dict indicating the dispatch was queued."""
    return {
        "status": "ACCEPTED",
        "procedure": procedure,
        "submissionId": payload.get("submissionSFDCId"),
        "transactionId": payload.get("transactionId"),
    }


# ---------------------------------------------------------------------------
# Background dispatch
# ---------------------------------------------------------------------------


def _dispatch_group_procedure(payload: dict, procedure: str) -> None:
    """
    Open a Snowflake connection and CALL the target writeback procedure.

    Runs on a daemon thread so the HTTP response is not blocked. The procedure
    receives the full payload as PARSE_JSON and an async_flag boolean.
    """
    sub_id = payload.get("submissionSFDCId")
    txn_id = payload.get("transactionId")
    async_flag = bool(payload.get("async_flag", False))
    logger.debug(
        "Dispatch starting: procedure=%s submissionId=%s transactionId=%s async_flag=%s",
        procedure, sub_id, txn_id, async_flag,
    )
    if DEBUG_MODE:
        logger.debug("Full dispatch payload: %s", json.dumps(payload, default=str))

    start = time.monotonic()
    conn = None
    cur = None
    try:
        conn = _open_connection()
        cur = conn.cursor()
        fq_procedure = f"{_quote_id(DB_NAME)}.{_quote_id(SCHEMA_NAME)}.{_quote_id(procedure)}"
        cur.execute(
            f"CALL {fq_procedure}(PARSE_JSON(%s), %s)",
            (json.dumps(payload), async_flag),
        )
        row = cur.fetchone()
        result = json.loads(row[0]) if row and row[0] is not None else None
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)
        status = result.get("status") if isinstance(result, dict) else result
        logger.info(
            "Dispatched %s for submissionId=%s transactionId=%s -> status=%s elapsed_ms=%s",
            procedure, sub_id, txn_id, status, elapsed_ms,
        )
        if DEBUG_MODE:
            logger.debug("Full procedure result: %s", json.dumps(result, default=str))
    except Exception:
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)
        logger.exception(
            "Background dispatch failed for procedure=%s submissionId=%s transactionId=%s elapsed_ms=%s",
            procedure, sub_id, txn_id, elapsed_ms,
        )
    finally:
        if cur is not None:
            try:
                cur.close()
            except Exception:
                pass
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/")
def healthz():
    """Readiness probe. SPCS polls this before routing traffic to the container."""
    return {"status": "ok"}


@app.post("/route")
async def route(request: Request):
    """
    Main routing endpoint.

    SPCS service functions send requests in batched format:
        {"data": [[0, <payload>], [1, <payload>], ...]}

    Each inner list is [row_index, json_payload]. For each row we look up the
    productCode, dispatch the matching stored procedure on a background thread,
    and return an ACCEPTED or FAILURE status synchronously.
    """
    body = await request.json()
    rows = body.get("data", [])
    logger.info("Received /route request with %d row(s)", len(rows))
    if DEBUG_MODE:
        logger.debug("Full request body: %s", json.dumps(body, default=str))

    out_rows = []
    for row in rows:
        if not isinstance(row, list) or len(row) < 2:
            logger.warning("Malformed row (expected [index, payload]): %s", row)
            row_number = row[0] if isinstance(row, list) and len(row) >= 1 else len(out_rows)
            out_rows.append([row_number, _failure("Malformed row: expected [index, payload]", {})])
            continue
        row_number, payload = row[0], row[1]
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except json.JSONDecodeError:
                logger.warning("Row %s: payload is not valid JSON, returning FAILURE", row_number)
                out_rows.append([row_number, _failure("Payload is not valid JSON", {})])
                continue

        product_code = (payload.get("productCode") or "").upper()
        procedure = PRODUCT_TO_PROCEDURE.get(product_code)

        if procedure is None:
            result = _failure(f"Unrecognized productCode: {product_code or '<missing>'}", payload)
        else:
            _executor.submit(_dispatch_group_procedure, payload, procedure)
            result = _accepted(payload, procedure)

        out_rows.append([row_number, result])

    return JSONResponse(status_code=200, content={"data": out_rows})
