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

**FrugalZeus** is a sovereign, zero-idle-waste **Internal Developer Platform (IDP)** reference architecture. It demonstrates an end-to-end GitOps delivery pipeline, localized cloud IaC emulation, unified OpenTelemetry observability, and granular FinOps cost attribution — all orchestrated on any Self-Hosted, Managed (GKE, AKS, EKS) Kubernetes cluster, or simply a k3s/kind cluster on a local VM.

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
| **GitOps** | **Argo CD** | App-of-Apps with `sync-waves` — infra first, tenants last |
| **Orchestration** | **k3s / Kubernetes** | Minimal-footprint distribution; no control-plane bloat |
| **Cloud Emulation** | **Floci** | In-cluster AWS API emulator — zero-cost S3/IaC testing |
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

```bash
make help             # All available targets
make bootstrap        # Full setup: cluster → Argo CD → GitOps → Floci → Terraform
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
```

---

## Repository Layout

```text
FrugalZeus/
├── k3s/                          # Bootstrap script (k3s provisioning + Argo CD setup)
├── scripts/                      # Platform utilities (port-forward, etc.)
├── terraform/                    # IaC definitions targeting Floci (AWS emulator)
├── microservice/                 # FastAPI app — OTel instrumented (metrics + traces)
├── platform-gitops/
│   ├── root-app.yaml             # Argo CD App-of-Apps entry point
│   ├── infrastructure/           # Helm Application manifests (monitoring, opencost, etc.)
│   └── tenants/
│       ├── base/                 # Shared guardrails: NetworkPolicy, Quota, LimitRange, ServiceMonitor
│       ├── team-alpha/           # Example tenant overlay
│       └── guestbook-overlay/    # NodePort supplement for guestbook demo app
├── docs/                         # MkDocs platform documentation
└── Makefile                      # All developer operations
```

---

## Documentation

Full platform documentation is available at the [GitHub Pages site](https://barbaria888.github.io/FrugalZeus/).

| Doc | Description |
| :--- | :--- |
| [Architecture](docs/docs/architecture.md) | Design decisions, sync-waves, OTel, and tenancy model |
| [Observability](docs/docs/observability.md) | LGTM stack — Prometheus, Loki, Tempo, Grafana correlation |
| [FinOps](docs/docs/finops.md) | OpenCost cost attribution and showback model |
| [Tenant Onboarding](docs/docs/onboarding.md) | Add a new team in < 5 minutes via GitOps |
