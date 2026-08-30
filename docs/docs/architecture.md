# Architecture & Technical Design Decisions

## Key Design Principles

1. **Zero-Cost Cloud Emulation**: By using **Floci** inside the k3s cluster, developers can test S3 bucket integrations using authentic AWS SDK calls without incurring AWS API costs or requiring live credentials.
2. **App-of-Apps GitOps**: Argo CD reconciles all cluster state from a single `root-app.yaml`. Sync waves ensure that infrastructure dependencies (Floci, Prometheus, Loki, Tempo) become `Healthy` before tenant workloads are applied.
3. **Single Instrumentation Layer**: OpenTelemetry (`opentelemetry-instrument`) auto-instruments the application runtime without manual metric counters or manual tracing code. OTel exports Prometheus metrics on port `9464` and OTLP traces to Tempo on port `4318`.
4. **Least-Privilege Tenant Guardrails**: Kustomize overlays ensure every tenant namespace receives enforced `ResourceQuota`, `LimitRange`, and strict `NetworkPolicy` rules preventing unauthorized cross-tenant communication.
