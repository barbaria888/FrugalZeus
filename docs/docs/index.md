# Flagship Platform Documentation

Welcome to the **Flagship Platform** developer portal. This platform is designed to provide automated, self-service infrastructure and application delivery for multi-tenant teams.

## Core Features

- **Automated GitOps Engine**: Argo CD synchronizes platform infrastructure and tenant workloads declaratively using the App-of-Apps pattern.
- **Local AWS Emulation**: Floci provides an in-cluster AWS API emulator for zero-cost S3 testing.
- **Infrastructure as Code**: Terraform provisions emulated cloud resources with standard AWS providers.
- **Unified Observability**: Single OpenTelemetry framework delivering metrics (Prometheus), logs (Loki), and traces (Tempo) into Grafana.
- **FinOps & Cost Allocation**: OpenCost provides real-time in-cluster cost tracking per namespace.
- **Self-Service Multi-Tenancy**: Standard Kustomize base templates enforce ResourceQuota, LimitRange, and NetworkPolicy guardrails automatically.
