# Architecture & Technical Design Decisions

This document details the core architectural tenets and the rationale behind the platform's engineering design.

## Key Architectural Principles

### 1. Deterministic GitOps Reconciliation
We utilize **Argo CD** employing the **App-of-Apps** pattern. State reconciliation is strictly ordered using `sync-waves` (`argocd.argoproj.io/sync-wave`). 
- **Waves 1-4**: Infrastructure capabilities (Floci, Prometheus, Loki, Tempo, OpenCost) are prioritized.
- **Wave 5+**: Tenant workloads are applied only after foundational dependencies achieve a `Healthy` state.
- **Server-Side Apply**: `ServerSideApply=true` is enforced across complex manifests (e.g., `kube-prometheus-stack` CRDs) to bypass client-side annotation payload limits.

### 2. Zero-Cost Emulation Layer
**Floci** operates as an in-cluster AWS emulator. 
- **Rationale**: Isolates development and CI environments from cloud provider unreliability and eliminates transient costs associated with integration testing.
- **Implementation**: Applications utilize standard AWS SDKs pointed at the internal Floci service endpoint. Terraform orchestrates simulated infrastructure (e.g., S3 buckets) directly against this emulator during the bootstrap phase.

### 3. OpenTelemetry Standardization
The platform mandates a single instrumentation layer.
- **Auto-Instrumentation**: Applications are instrumented utilizing `opentelemetry-instrument`, abstracting telemetry generation from business logic.
- **Topology**: OTel exports Prometheus metrics via port `9464` and OTLP distributed traces to Tempo via port `4318`. Grafana provides the unified visualization layer for correlation.

### 4. Zero-Trust Multi-Tenancy
Tenant namespaces operate under enforced least-privilege guardrails, injected via Kustomize base overlays.
- **ResourceQuotas & LimitRanges**: Prevent noisy-neighbor scenarios by capping compute and memory consumption at the namespace level.
- **NetworkPolicies**: Default-deny ingress/egress configurations ensure lateral movement between tenant boundaries is strictly prohibited unless explicitly authorized.

### 5. NodePort Ingress Strategy
For local development and constrained environment topologies, core services are exposed directly via defined `NodePort` interfaces, bypassing complex dynamic Ingress controllers while maintaining predictable endpoint accessibility (`30000` for Grafana, `30080` for Argo CD, etc.).
