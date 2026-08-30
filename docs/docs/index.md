# Flagship Platform Documentation

Welcome to the **Flagship Platform** internal developer portal. This documentation outlines the architectural blueprints, operational constraints, and engineering standards for our sovereign, multi-tenant Internal Developer Platform (IDP).

## Platform Philosophy

The platform is designed around the principles of **Zero-Idle Waste**, **Declarative State**, and **Autonomous Tenancy**. It provides a hardened, self-service infrastructure baseline enabling engineering teams to deliver capabilities without friction, while maintaining strict organizational governance over cost, security, and observability.

## Core Capabilities

- **GitOps Orchestration**: Argo CD acts as the single source of truth, leveraging the App-of-Apps pattern and deterministic sync waves to reconcile infrastructure dependencies before tenant workloads.
- **Localized Cloud Emulation**: Integration of Floci provides an in-cluster AWS API emulation layer. This permits localized IaC (Terraform) execution and application SDK validation without incurring external cloud latency or cost.
- **Unified Telemetry (LGTM)**: A standardized OpenTelemetry framework that aggregates metrics, logs, and traces into a centralized Grafana pane, enabling rapid MTTR through deep correlation.
- **In-Cluster FinOps**: OpenCost integration provides real-time, deterministic cost attribution at the namespace level, enabling accurate showback and enforcing financial accountability.
- **Hardened Multi-Tenancy**: Tenant isolation is guaranteed via Kustomize base templates that automatically inject non-negotiable `NetworkPolicy`, `LimitRange`, and `ResourceQuota` constraints.
