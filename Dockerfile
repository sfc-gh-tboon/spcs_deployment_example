# =============================================================================
# SPCS API Proxy Service - Dockerfile
# =============================================================================
# Build context: repo root
# Target platform: linux/amd64  (required for SPCS)
#
# Build:
#   docker buildx build --platform linux/amd64 -t <registry>/my_service:latest .
#
# Run locally for testing (token passed as env var):
#   docker run -p 8080:8080 \
#     -e API_TOKEN="your-token-here" \
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
EXPOSE 8080

# Gunicorn: production WSGI server
#   --workers 4       : 4 processes; each maintains its own persistent HTTP session
#   --timeout 60      : worker timeout; set above REQUEST_TIMEOUT_S (default 30s)
#   --access-logfile - : route access logs to stdout so SPCS captures them
CMD ["gunicorn", \
     "--workers=4", \
     "--bind=0.0.0.0:8080", \
     "--timeout=60", \
     "--access-logfile=-", \
     "main:app"]
