# =============================================================================
# SPCS Writeback Route Function - Dockerfile
# =============================================================================
# Build context: repo root
# Target platform: linux/amd64  (required for SPCS)
#
# Build:
#   docker buildx build --platform linux/amd64 -t <registry>/my_service:latest .
#
# Run locally for testing (requires Snowflake env vars):
#   docker run -p 8000:8000 \
#     -e SNOWFLAKE_HOST="..." \
#     -e SNOWFLAKE_ACCOUNT="..." \
#     -e WRITEBACK_DB_NAME="..." \
#     -e WRITEBACK_SCHEMA_NAME="..." \
#     -e WRITEBACK_WAREHOUSE="..." \
#     <registry>/my_service:latest
# =============================================================================

FROM python:3.12-slim

# Non-root user - required by Snowflake security policy
RUN adduser --disabled-password --gecos "" appuser

WORKDIR /app

# Copy application code and dependencies
COPY app/ .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Switch to non-root before starting the process
USER appuser

# Port must match the endpoint port in the service spec
EXPOSE 8000

# Uvicorn: production ASGI server
#   --workers 4       : 4 processes for concurrent request handling
#   --host 0.0.0.0    : bind to all interfaces so SPCS can reach the container
#   --port 8000       : must match EXPOSE and service spec endpoint port
CMD ["uvicorn", \
     "main:app", \
     "--workers=4", \
     "--host=0.0.0.0", \
     "--port=8000"]
