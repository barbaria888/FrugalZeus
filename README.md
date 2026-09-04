<div align="center">

<img src="images/diorama-zeus.png" alt="FrugalZeus Platform" width="100%"/>

# FrugalZeus ⚜️

## Cloud-Native Engineering Platform


<br/>

[![Build & Deploy Microservice](https://github.com/barbaria888/FrugalZeus/actions/workflows/ci-build-push.yml/badge.svg)](https://github.com/barbaria888/FrugalZeus/actions/workflows/ci-build-push.yml)
[![Deploy Documentation](https://github.com/barbaria888/FrugalZeus/actions/workflows/docs-deploy.yml/badge.svg)](https://github.com/barbaria888/FrugalZeus/actions/workflows/docs-deploy.yml)
[![Observability](https://img.shields.io/badge/Observability-LGTM%20Stack-orange?logo=grafana)](https://grafana.com/)
[![FinOps](https://img.shields.io/badge/FinOps-OpenCost-brightgreen)](https://www.opencost.io/)

</div>

---

**FrugalZeus** is a sovereign, zero-idle-waste **Internal Developer Platform (IDP)** reference architecture. It features a **config-driven multi-environment application deployment system** (`test` / `stage` / `prod`), an end-to-end GitOps delivery pipeline, localized cloud IaC emulation, unified OpenTelemetry observability, and granular FinOps cost attribution — all orchestrated on any Self-Hosted, Managed (GKE, AKS, EKS) Kubernetes cluster, or simply a k3s/kind cluster on a local VM.

> **Lightweight** and **frugal** for pure signal. Built for Platform Architects and Engineering Teams.

---

## Platform Architecture

<details open>
<summary><strong>App-of-Apps Topology (click to expand)</strong></summary>
<br/>
<img src="https://github.com/barbaria888/FrugalZeus/blob/main/images/Architecture.png"/>

</details>

---

## Platform Capabilities

| Capability | Component | Design Decision |
| :--- | :--- | :--- |
| **Config-Driven Apps** | **`apps/*/config.yaml`** | Single config file per app; zero Argo CD / Kustomize internal authoring required by devs |
| **Multi-Env GitOps** | **Matrix ApplicationSet** | Combines Git file generator × environment list to auto-generate `test`, `stage`, and `prod` apps |
| **GitOps Engine** | **Argo CD** | App-of-Apps with `sync-waves` — infra first, tenant applications last |
| **Orchestration** | **k3s / Kubernetes** | Minimal-footprint distribution; no control-plane bloat |
| **Cloud Emulation** | **Floci** | In-cluster AWS API emulator — zero-cost S3/IaC testing |
| **Secrets** | **Vault + ESO** | Zero secrets in Git — runtime delivery via Kubernetes auth; `make vault-seed` to write, `make vault-status` to verify |
| **Observability** | **LGTM Stack** | OpenTelemetry → Prometheus + Loki + Tempo, unified in Grafana |
| **FinOps** | **OpenCost** | Real-time namespace cost attribution from Prometheus telemetry |
| **Multi-Tenancy** | **Kustomize** | Immutable base overlays: `NetworkPolicy`, `ResourceQuota`, `LimitRange` |
| **Service Access** | **NodePort + Port-Forward** | NodePorts for direct VM access; `make ports` for localhost |

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/barbaria888/FrugalZeus.git
cd FrugalZeus

# 2. Bootstrap (choose: new k3s or existing cluster)
make bootstrap

# 3. Wait for full platform sync
make sync-wait

# 4. Patch all NodePort services (direct VM access — no port-forward needed)
make patch-nodeports

# 5. See all live endpoints + credentials
make observe
```

**Platform endpoints after bootstrap:**

| Service | NodePort (VM) | Localhost (`make ports`) | Credentials |
| :--- | :--- | :--- | :--- |
| **Grafana** | `http://<VM-IP>:30000` | `http://localhost:3000` | `admin / platform-admin` |
| **Argo CD** | `http://<VM-IP>:30080` | `http://localhost:8080` | `admin / make password` |
| **Guestbook** | `http://<VM-IP>:30800` | `http://localhost:8000` | — |
| **OpenCost** | `http://<VM-IP>:30903` | `http://localhost:9003` | — |

---

## 🛠 Developer Operations

### Application Operations (Config-Driven GitOps)

```bash
make apps                          # List all onboarded developer application configs
make validate-app APP=guestbook    # Validate apps/guestbook/config.yaml using yq
make deploy APP=guestbook          # Validate, git commit, and push config to trigger GitOps
make status-app APP=guestbook      # Check Argo CD sync status across test/stage/prod
make promote APP=guestbook         # Print guidance for environment promotion
make destroy APP=guestbook         # Delete application config and trigger Argo CD pruning
```

### Platform & Infrastructure Operations

```bash
make help             # All available targets
make bootstrap        # Full setup: cluster → Argo CD → GitOps → Floci → Vault → Terraform
make apply-apps       # Apply all Argo CD Application manifests (server-side, safe for CRDs)
make sync-wait        # Wait for all apps to reach Synced+Healthy (up to 10 min)
make patch-nodeports  # Force-patch all services to NodePort after sync
make ports            # Open verified localhost port-forwards (3000/8080/8000/9003)
make nodeports        # Verify live NodePort assignments on cluster
make observe          # Print all endpoints, datasources, and credentials
make status           # Cluster health: nodes, apps, pods, services
make test             # Smoke test all endpoints
make password         # Get Argo CD admin password
make clean            # Destroy local k3s cluster

# Secrets (Vault + ESO)
make vault-init       # One-shot: init Vault, configure k8s auth, seed demo secrets
make vault-seed KEY=MY_SECRET VALUE=val  # Write/update a secret in Vault
make vault-status     # Check Vault pod + ExternalSecret sync state
```

---

## Repository Layout

```text
FrugalZeus/
├── apps/                         # ← Developer applications (config.yaml per app)
│   ├── guestbook/                # Guestbook multi-environment config
│   └── online-boutique/          # Online Boutique multi-environment config
├── k3s/                          # Bootstrap script (k3s provisioning + Argo CD setup)
├── scripts/                      # Platform scripts (validate-app-config.sh, port-forward.sh, vault-init.sh)
├── terraform/                    # IaC definitions targeting Floci (AWS emulator)
├── microservice/                 # FastAPI app — OTel instrumented (metrics + traces)
├── platform-gitops/
│   ├── root-app.yaml             # Argo CD App-of-Apps entry point
│   ├── infrastructure/           # Application manifests & ApplicationSets (includes vault.yaml, external-secrets.yaml)
│   ├── infrastructure-manifests/
│   │   ├── vault/                # ClusterSecretStore — platform-owned, synced by vault-config ArgoCD app
│   │   └── ...                   # Other infra manifests (floci, argocd)
│   └── tenants/
│       ├── base/                 # Shared guardrails: NetworkPolicy, Quota, LimitRange, ServiceMonitor
│       ├── team-alpha/           # Example tenant overlay (includes external-secret.yaml)
│       └── guestbook-overlay/    # NodePort supplement for guestbook demo app
├── docs/                         # MkDocs platform documentation
└── Makefile                      # All developer & platform operations
```

---

## Documentation

Full platform documentation is available at the [GitHub Pages site](https://barbaria888.github.io/FrugalZeus/).

| Doc | Description |
| :--- | :--- |
| [Architecture](docs/docs/architecture.md) | Design decisions, sync-waves, OTel, and tenancy model |
| [Observability](docs/docs/observability.md) | LGTM stack — Prometheus, Loki, Tempo, Grafana correlation |
| [FinOps](docs/docs/finops.md) | OpenCost cost attribution and showback model |
| [Tenant Onboarding](docs/docs/onboarding.md) | Config-driven app deployment & team onboarding in < 5 minutes |
