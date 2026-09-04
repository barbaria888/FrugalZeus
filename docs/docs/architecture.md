# Architecture & Technical Design

This document details the architectural blueprints, control-plane topology, and technical design decisions governing the **FrugalZeus** platform.

---

## High-Level Topology

The platform enforces strict separation of concerns across the Kubernetes control plane, developer config-driven application layer, shared infrastructure capabilities, and autonomous tenant boundaries.

```mermaid
graph TB
    subgraph "Secrets Pipeline (Zero-Trust)"
        Vault["HashiCorp Vault (KV-v2)"]
        ESO["External Secrets Operator"]
        CSS["ClusterSecretStore"]
    end

    subgraph "Developer Abstraction Layer (apps/)"
        DevConfig["apps/<name>/config.yaml"]
        MakeCLI["Makefile CLI (make deploy)"]
    end

    subgraph "Cluster Control Plane (k3s / K8s)"
        API["kube-apiserver"]
        ArgoCD["Argo CD Controller"]
        MatrixAppSet["apps-from-config ApplicationSet"]
        TenantAppSet["tenant-applications ApplicationSet"]
    end

    subgraph "Platform Infrastructure (Namespace: platform-infra)"
        Floci["Floci (AWS S3/IAM Emulator)"]
        TF["Terraform State / S3 Buckets"]
    end

    subgraph "Telemetry Core (Namespace: monitoring)"
        Prom["Prometheus TSDB"]
        Loki["Grafana Loki"]
        Tempo["Grafana Tempo"]
        Grafana["Grafana Portal"]
        Promtail["Promtail DaemonSet"]
    end

    subgraph "Cost Governance (Namespace: opencost)"
        OpenCost["OpenCost Engine"]
    end

    subgraph "Tenant Multi-Env Workloads (Namespace: tenant-<app>-<env>)"
        Workload["Multi-Env App Pods (guestbook, online-boutique)"]
        OTel["OpenTelemetry Instrumentation"]
        Guardrails["NetworkPolicy · ResourceQuota · LimitRange"]
    end

    %% Secrets flow
    Vault -->|"KV-v2 secret values"| ESO
    CSS -->|"auth/kubernetes role"| Vault
    ESO -->|"creates k8s Secrets"| Workload
    ArgoCD -->|"Reconciles State"| ESO

    %% Developer Flow
    DevConfig --> MakeCLI
    MakeCLI -->|"Pushes GitOps Config"| MatrixAppSet

    %% State Management
    ArgoCD -->|"Reconciles State"| Floci
    ArgoCD -->|"Reconciles State"| Prom
    ArgoCD -->|"Reconciles State"| Loki
    ArgoCD -->|"Reconciles State"| Tempo
    ArgoCD -->|"Reconciles State"| OpenCost
    MatrixAppSet -->|"Generates test/stage/prod Apps"| Workload
    TenantAppSet -->|"Discovers & Deploys"| Workload

    %% Telemetry & Data Flow
    Workload -->|"OTLP Traces :4318"| Tempo
    Workload -->|"Scrapes /metrics :9464"| Prom
    Promtail -->|"Container Logs"| Loki
    OpenCost -->|"PromQL Queries :9090"| Prom
    Grafana -->|"Queries"| Prom & Loki & Tempo

    %% Local Emulation
    Workload -->|"AWS SDK S3 Calls :4566"| Floci
```

---

## Declarative GitOps Architecture

FrugalZeus implements a **Two-Tier App-of-Apps and ApplicationSet** delivery model.

### 1. The App-of-Apps Pattern (`platform-root`)
The root application (`platform-gitops/root-app.yaml`) watches the repository's `platform-gitops/infrastructure/` directory. When applied, Argo CD cascades reconciliation across all shared infrastructure components, including the developer ApplicationSet.

```mermaid
flowchart TD
    Root["platform-root (Root Application)"]

    Root --> Wave1["Wave 1: Cloud Emulation (Floci) · Secrets Store (Vault)"]
    Root --> Wave2["Wave 2: ESO Operator · Monitoring Core (Prometheus & Grafana)"]
    Root --> Wave3["Wave 3: ClusterSecretStore · Telemetry Backends (Loki & Tempo)"]
    Root --> Wave4["Wave 4: FinOps Engine (OpenCost)"]
    Root --> Wave5["Wave 5: Config-Driven ApplicationSet & Tenants (ExternalSecrets synced)"]
    Root --> Wave6["Wave 6: NodePort Exposure Supplements"]
```

### 2. Matrix ApplicationSet Generator (`apps-from-config.yaml`)

To shield developers from Argo CD internal manifests, the platform provides an **ApplicationSet Matrix Generator**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-from-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://github.com/barbaria888/FrugalZeus.git
              revision: main
              files:
                - path: "apps/*/config.yaml"
          - list:
              elements:
                - env: test
                - env: stage
                - env: prod
  template:
    metadata:
      name: "{{ .name }}-{{ .env }}"
      namespace: argocd
      labels:
        platform.io/app: "{{ .name }}"
        platform.io/env: "{{ .env }}"
        platform.io/team: "{{ .team }}"
      annotations:
        argocd.argoproj.io/sync-wave: "5"
    spec:
      project: default
      source:
        repoURL: "{{ .source.repoURL }}"
        targetRevision: "{{ .source.targetRevision }}"
        path: "{{ .source.path }}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "tenant-{{ .name }}-{{ .env }}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

### 3. Deterministic Sync-Waves
To prevent race conditions during cold cluster boots, resources are ordered using the `argocd.argoproj.io/sync-wave` annotation:

| Sync Wave | Applications | Purpose & Dependencies |
| :--- | :--- | :--- |
| **Wave 1** | `floci`, `vault` | Cloud mocking layer + Vault secrets store. Vault must be up before ESO attempts auth. |
| **Wave 2** | `external-secrets`, `kube-prometheus-stack` | ESO Operator installs CRDs. Prometheus CRDs for `ServiceMonitor`. |
| **Wave 3** | `vault-config`, `loki`, `tempo` | `ClusterSecretStore` applied after ESO CRDs exist. Log and trace ingestors. |
| **Wave 4** | `opencost` | Cost engine depending on Prometheus TSDB scraping endpoints. |
| **Wave 5** | `apps-from-config`, `tenant-applications` | ExternalSecrets sync from Vault → k8s Secrets created before pods start. |
| **Wave 6** | `guestbook-nodeport` | Supplementary access overlays for external NodePort access. |

!!! tip "Server-Side Apply"
    Complex Helm charts such as `kube-prometheus-stack` contain Custom Resource Definitions (CRDs) whose schema annotations exceed the standard `kubectl.kubernetes.io/last-applied-configuration` limit (262,144 bytes). FrugalZeus enforces `ServerSideApply=true` on all Argo CD application specs to prevent deployment failures.

---

## Secrets Pipeline (Vault + ESO)

FrugalZeus uses **HashiCorp Vault OSS + External Secrets Operator** to deliver secrets to tenant workloads at runtime. No secret values are ever committed to Git.

```mermaid
flowchart LR
    Git["Git Repo\n(ExternalSecret YAML\npath + key only)"] --> ArgoCD
    ArgoCD -->|sync| ESO["External Secrets\nOperator"]
    ESO -->|Kubernetes JWT auth| Vault["HashiCorp Vault\n(KV-v2 values)"]
    Vault -->|secret values| ESO
    ESO -->|creates| KSecret["k8s Secret\n(team-alpha-secret)"]
    KSecret -->|secretKeyRef| Pod["Tenant Pod"]
```

### How it works

1. **Operator** seeds values into Vault once: `make vault-seed KEY=DB_PASSWORD VALUE=prod-pass`
2. **Git** holds an `ExternalSecret` manifest — only the Vault path and key name, never the value
3. **ArgoCD** syncs the `ExternalSecret` into the tenant namespace
4. **ESO** authenticates to Vault using its own Kubernetes ServiceAccount JWT (no static credentials)
5. **ESO** reads the value and creates a standard `k8s Secret` in the tenant namespace
6. **Tenant pod** reads the secret via `secretKeyRef` — no Vault knowledge required

### Developer workflow

```bash
# Check if secrets are synced
make vault-status

# Add or update a secret value
make vault-seed KEY=MY_SECRET VALUE=my-value

# Then add the key to external-secret.yaml in your tenant overlay and push
```

!!! note "Zero secrets in Git"
    `external-secret.yaml` contains only the Vault **path** and **key name**. Values never appear in Git history.

---

## Multi-Tenancy & Zero-Trust Isolation

Tenant isolation is implemented through immutable Kustomize overlays stamped out from `platform-gitops/tenants/base/` across all generated environment namespaces (`tenant-<app>-<env>`).

```mermaid
graph LR
    subgraph "Tenant Isolation Boundary"
        direction TB
        NP["NetworkPolicy<br/>(Default-Deny Ingress/Egress)"]
        RQ["ResourceQuota<br/>(Hard Compute Caps)"]
        LR["LimitRange<br/>(Default Pod Limits)"]
        SM["ServiceMonitor<br/>(Automated Discovery)"]
    end

    TenantPod["Tenant Pod"] --- NP
    TenantPod --- RQ
    TenantPod --- LR
    TenantPod --- SM
```

### 1. Network Microsegmentation
The platform applies a default-restricted `NetworkPolicy` to every tenant namespace:
- **Allowed Ingress**: Intra-namespace traffic, Prometheus scraper (port `9464`), and local port-forwarding proxies from `kube-system`.
- **Allowed Egress**: CoreDNS (`kube-system:53`), Kubernetes API (`default:443`), Floci S3 emulator (`platform-infra:4566`), and Tempo OTLP gateway (`monitoring:4318`).
- **Blocked**: Direct cross-tenant pod-to-pod communication is denied at the CNI layer.

### 2. Noisy-Neighbor Mitigation
- **ResourceQuotas**: Enforce maximum CPU (1-2 Cores), Memory (1-2 GiB), and Pod count (10 Pods) per namespace.
- **LimitRanges**: Automatically inject default request/limit values on pods lacking explicit declarations, ensuring predictable scheduling.

---

## Service Exposure Architecture

FrugalZeus supports both remote/VM access via **NodePorts** and local developer forwarding via **`make ports`**.

```mermaid
flowchart LR
    subgraph "Host / Remote Client"
        Browser["Web Browser / Client"]
    end

    subgraph "Service Layer"
        NP1["NodePort :30000"] --> Grafana["Grafana (:80)"]
        NP2["NodePort :30080"] --> ArgoCD["Argo CD (:80)"]
        NP3["NodePort :30800"] --> Guestbook["Guestbook (:80)"]
        NP4["NodePort :30903"] --> OpenCost["OpenCost (:9003)"]
    end

    Browser -->|"Direct VM Access"| NP1 & NP2 & NP3 & NP4
    Browser -->|"make ports (Localhost)"| Grafana & ArgoCD & Guestbook & OpenCost
```

| Component | Target Namespace | Target Port | Assigned NodePort | Localhost Forward |
| :--- | :--- | :--- | :--- | :--- |
| **Grafana** | `monitoring` | `80` (HTTP) | `30000` | `http://localhost:3000` |
| **Argo CD** | `argocd` | `80` (Insecure HTTP) | `30080` | `http://localhost:8080` |
| **Tenant App** | `tenant-guestbook` | `80` (HTTP) | `30800` | `http://localhost:8000` |
| **OpenCost** | `opencost` | `9003` (HTTP) | `30903` | `http://localhost:9003` |

---

## Local Cloud Emulation (Floci)

Rather than maintaining costly external AWS resources or running heavyweight alternatives like LocalStack, FrugalZeus integrates **Floci**:
1. Microservices communicate with standard AWS SDKs using `AWS_ENDPOINT_URL=http://floci.platform-infra.svc.cluster.local:4566`.
2. Terraform manifests (`terraform/`) run against Floci during `make bootstrap` to provision buckets and IAM roles idempotently.
3. Completely sovereign: operates seamlessly in air-gapped environments or without internet access.
