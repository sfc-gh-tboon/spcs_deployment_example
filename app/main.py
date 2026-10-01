"""
SPCS API Proxy Service
======================
A Flask service that proxies requests to an external API.
Deployed as a Snowpark Container Services (SPCS) service and called
from SQL via a service function.

How it works:
  1. Snowflake executes:  SELECT FETCH_<NAME>_RESPONSE(PARSE_JSON('...'))
  2. The service function routes that call to POST /proxy on this container
  3. This service forwards the payload to the target API and returns the result
  4. Snowflake receives the JSON and returns it to the caller

Endpoints:
  GET  /        Health / readiness probe (SPCS checks this before routing traffic)
  POST /proxy   Main proxy endpoint; accepts a JSON body, returns JSON
"""

import os
import logging
import time

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from flask import Flask, request, jsonify

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("spcs_proxy")

# ---------------------------------------------------------------------------
# Configuration  (injected by SPCS at container start via secret binding)
# ---------------------------------------------------------------------------
API_TOKEN       = os.environ["API_TOKEN"]              # required - crashes on start if missing
API_HEADER_KEY  = os.environ.get("API_HEADER_KEY", "") # optional extra header (e.g. subscription key)
TARGET_URL      = os.environ.get("TARGET_URL", "https://postman-echo.com/post")
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT_S", "30"))

# ---------------------------------------------------------------------------
# Persistent HTTP session  (module-level - one per Gunicorn worker process)
# ---------------------------------------------------------------------------
# TCP + TLS connections are reused across requests (no handshake overhead).
# Automatic retry on transient 502/503/504 responses with exponential backoff.

_http = requests.Session()
_http.headers.update({
    "Content-Type": "application/json",
    "Authorization": f"Bearer {API_TOKEN}",
    **({"ocp-apim-subscription-key": API_HEADER_KEY} if API_HEADER_KEY else {}),
})
_retry = Retry(total=2, backoff_factor=0.3, status_forcelist=[502, 503, 504])
_http.mount("https://", HTTPAdapter(pool_connections=1, pool_maxsize=8, max_retries=_retry))

logger.info("HTTP session initialised; TARGET_URL=%s timeout=%ss", TARGET_URL, REQUEST_TIMEOUT)

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)


@app.get("/")
def healthcheck():
    """
    Readiness probe.  SPCS polls this endpoint before routing any traffic
    to the container.  Return 200 as soon as the service is ready.
    """
    return jsonify({"status": "ok"})


@app.post("/proxy")
def proxy_request():
    """
    Main proxy endpoint.

    SPCS service functions send requests in this shape:
        {"data": [[0, <arg1>], [1, <arg1>], ...]}

    Each inner list is one row: [row_index, argument_value].
    We must return results in the same format:
        {"data": [[0, <result1>], [1, <result2>], ...]}

    If the API call fails for a row, we return an error dict for that
    row rather than failing the whole batch.
    """
    body = request.get_json(silent=True)
    if body is None or "data" not in body:
        return jsonify({"error": "missing 'data' key in request body"}), 400

    results = []
    for row_index, payload in body["data"]:
        result = _call_api(payload, row_index)
        results.append([row_index, result])

    return jsonify({"data": results})


def _call_api(payload, row_index: int):
    """Call the target API for a single row. Returns response dict or error dict."""
    start = time.perf_counter()
    try:
        resp = _http.post(TARGET_URL, json=payload, timeout=REQUEST_TIMEOUT)
        elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.info("row=%s status=%s elapsed_ms=%s", row_index, resp.status_code, elapsed_ms)
        if resp.status_code == 200:
            return resp.json()
        return {"error": resp.status_code, "message": resp.text[:500]}
    except Exception as exc:
        elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
        logger.error("row=%s error=%s elapsed_ms=%s", row_index, exc, elapsed_ms)
        return {"error": "Exception", "message": str(exc)}
