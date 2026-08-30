# Unified Observability Strategy

The platform standardizes on the **LGTM** (Loki, Grafana, Tempo, Metrics/Prometheus) stack, underpinned by **OpenTelemetry (OTel)**. This architecture eliminates fragmented telemetry collection and provides deterministic, cross-pillar correlation.

## 1. Metrics (Prometheus)

Prometheus handles high-cardinality time-series data aggregation.
- **Service Discovery**: The Prometheus Operator utilizes `ServiceMonitor` resources to dynamically discover endpoints. Any service labeled with `platform.io/tenant: "true"` is automatically scraped.
- **Query Execution**: Metrics are queried via PromQL in Grafana.
  ```promql
  # Example: 99th percentile response time for tenant services
  histogram_quantile(0.99, sum(rate(http_server_request_duration_seconds_bucket{namespace=~"tenant-.*"}[5m])) by (le, service_name))
  ```

## 2. Distributed Tracing (Tempo)

Tempo provides high-volume, cost-effective distributed tracing.
- **Ingestion**: Microservices utilizing `opentelemetry-instrument` push OTLP payloads directly to the Tempo gateway (`http://tempo.monitoring.svc.cluster.local:4318`).
- **Correlation**: Trace IDs are injected into the logging context, allowing Grafana to pivot instantly from a log line to a full distributed trace waterfall.

## 3. Log Aggregation (Loki)

Loki acts as the horizontally scalable log aggregation system, architected for efficiency by indexing only metadata rather than full-text.
- **Log Routing**: Promtail daemonsets scrape container `stdout`/`stderr`, automatically enriching payloads with Kubernetes metadata (`namespace`, `pod`, `container`).
- **Query Execution**: Logs are parsed dynamically at read-time via LogQL.
  ```logql
  # Example: Isolate error rates across tenant workloads
  {namespace=~"tenant-.*"} |= "level=error" | json
  ```

## The Correlation Workflow

Grafana serves as the unified observability pane. The explicit design intent is a seamless investigative flow:
1. Identify degradation via a **Prometheus** alert or dashboard panel.
2. Pivot to **Loki** using the exact timestamp and pod labels to view surrounding log context.
3. Extract the `trace_id` from the log line to render the **Tempo** waterfall graph, isolating the exact function call or external API request causing the latency.
