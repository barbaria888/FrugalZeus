FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000 9464

# OTel auto-instrumentation wraps uvicorn.
# Instruments FastAPI + boto3 with zero code changes.
# Metrics on 9464/metrics, traces to Tempo via OTLP HTTP.
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
