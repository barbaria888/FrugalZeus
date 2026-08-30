# Observability Guide

The platform integrates all three pillars of observability into Grafana using OpenTelemetry standards.

## 1. Metrics (Prometheus)

- **Scraping**: Prometheus automatically discovers tenant workloads using `ServiceMonitor` resources matching label `platform.io/tenant: "true"`.
- **Query Example**:
  ```promql
  http_server_request_duration_seconds_bucket{service_name="team-alpha-svc"}
  ```

## 2. Logs (Loki + Promtail)

- **Collection**: Promtail collects container `stdout`/`stderr` logs and tags them with Kubernetes metadata (`namespace`, `pod`, `container`).
- **LogQL Example**:
  ```logql
  {namespace="tenant-team-alpha"} |= "upload"
  ```

## 3. Distributed Tracing (Tempo)

- **Ingestion**: Microservices send OTLP HTTP traces directly to `http://tempo.monitoring.svc.cluster.local:4318`.
- **Grafana Correlation**: You can jump seamlessly from a Prometheus latency spike to Loki logs and click into Tempo trace waterfalls to isolate slow S3 operations.
