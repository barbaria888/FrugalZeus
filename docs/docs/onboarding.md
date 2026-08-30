# Tenant Onboarding Contract

This document defines the automated procedure for provisioning a new tenant environment. The platform enforces a declarative, GitOps-driven onboarding flow that guarantees security compliance, automated service discovery, and immediate observability coverage.

---

## Pre-requisites: Run the Platform Bootstrap

Before any tenant can be observed, the platform infrastructure stack must be fully synced via Argo CD:

```bash
# 1. Bootstrap the cluster and install all infrastructure
make bootstrap

# 2. Wait for ALL Argo CD applications to reach Synced + Healthy state
make sync-wait

# 3. Open all verified local port-forwards
make ports

# 4. Print all observability endpoints and credentials
make observe
```

After `make ports`, the following platform services are accessible:

| Service | Local URL | Credentials |
| :--- | :--- | :--- |
| **Grafana** | http://localhost:3000 | `admin` / `platform-admin` |
| **Argo CD** | http://localhost:8080 | `admin` / `<make password>` |
| **Guestbook App** | http://localhost:8000 | — |
| **OpenCost** | http://localhost:9003 | — |

---

## Grafana: Pre-wired Observability Stack

The `kube-prometheus-stack` Helm deployment provisions Grafana with **three datasources pre-configured** by Helm sidecar injection. No manual wiring required after sync.

### Datasources

| Datasource | Type | Source | Purpose |
| :--- | :--- | :--- | :--- |
| **Prometheus** | `prometheus` | `kube-prometheus-stack` | Metrics from all `ServiceMonitor`-discovered pods |
| **Loki** | `loki` | `http://loki.monitoring.svc.cluster.local:3100` | Container logs shipped by Promtail |
| **Tempo** | `tempo` | `http://tempo.monitoring.svc.cluster.local:3100` | Distributed traces via OTLP |

### How Logs, Metrics, and Traces Flow

```
Tenant Pods
  ├── OTLP Traces  -->  Tempo   --> Grafana (Explore > Tempo)
  ├── /metrics     -->  Prometheus via ServiceMonitor  --> Grafana (Dashboards)
  └── stdout/stderr --> Promtail --> Loki --> Grafana (Explore > Loki)
```

For any namespace with `platform.io/tenant: "true"` labels, the base `ServiceMonitor` in `platform-gitops/tenants/base/service-monitor.yaml` automatically scrapes pods exposing a `metrics` port.

---

## Guestbook Demo Application

The platform hosts the canonical Argo CD **guestbook** reference application as the primary tenant demonstration workload.

```
Argo CD App:   guestbook-demo
Namespace:     tenant-guestbook
Source:        https://github.com/argoproj/argocd-example-apps.git / path: guestbook
Sync Policy:   Automated (prune + selfHeal)
```

This app syncs at **Sync Wave 5**, after all infrastructure (Prometheus, Loki, Tempo, OpenCost) is healthy.

---

## Onboarding a New Tenant

### 1. Copy the Tenant Baseline

```bash
cp -r platform-gitops/tenants/team-alpha platform-gitops/tenants/team-beta
```

### 2. Configure Tenant Metadata

Edit `platform-gitops/tenants/team-beta/kustomization.yaml`:

```yaml
namespace: tenant-team-beta
commonLabels:
  team: beta
  platform.io/tenant: "true"
```

### 3. Automatic Discovery via ApplicationSet

The `tenant-applications` ApplicationSet (in `platform-gitops/infrastructure/tenants-applicationset.yaml`) scans all directories under `platform-gitops/tenants/` (excluding `base`) and automatically generates Argo CD Applications for each.

**No manual Argo CD Application file is required.** Simply commit the tenant directory and push.

### 4. Commit and Push

```bash
git add platform-gitops/tenants/team-beta/
git commit -m "feat(platform): provision tenant-team-beta environment"
git push
```

**Expected Outcome**: The ApplicationSet controller creates a `tenant-team-beta` Argo CD Application, which provisions the namespace, enforces `NetworkPolicy`, `ResourceQuota`, `LimitRange`, and `ServiceMonitor` from the base overlay — automatically.

### 5. Verify Tenant is Synced and Observable

```bash
make sync-wait       # Wait for tenant app to go Healthy
make observe         # Print all endpoint URLs
```

Open Grafana at `http://localhost:3000`:
- **Explore > Loki**: Query `{namespace="tenant-team-beta"}` for container logs
- **Explore > Tempo**: Search for traces if the workload is OTel-instrumented
- **Dashboards > Kubernetes / Compute Resources / Namespace**: Select `tenant-team-beta` for CPU/memory
- **OpenCost** at `http://localhost:9003`: Cost breakdown by namespace
