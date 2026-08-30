# FrugalZeus — Cloud-Native Platform Engineering & FinOps

[![GitOps](https://img.shields.io/badge/GitOps-Argo%20CD-orange)](https://argoproj.github.io/cd/)
[![IaC](https://img.shields.io/badge/IaC-Terraform-blue)](https://www.terraform.io/)
[![Runtime](https://img.shields.io/badge/Kubernetes-k3s-lightgrey)](https://k3s.io/)
[![Observability](https://img.shields.io/badge/Observability-Prometheus%20%7C%20Loki%20%7C%20Tempo-red)](https://grafana.com/)
[![FinOps](https://img.shields.io/badge/FinOps-OpenCost-green)](https://www.opencost.io/)

> **FrugalZeus**: Sovereign platform authority with zero idle waste. A lightweight, multi-tenant Internal Developer Platform demonstrating end-to-end GitOps delivery, local cloud IaC simulation, unified OpenTelemetry observability, and sub-namespace FinOps cost attribution on a single Linux VM.

---

## Architectural Stack

| Layer | Tooling | Purpose |
| --- | --- | --- |
| **Cluster Runtime** | k3s on single Linux VM | Lightweight Kubernetes control plane and worker node. |
| **Infrastructure as Code** | Terraform | Provisions simulated AWS infrastructure (S3) against Floci. |
| **Cloud Simulation** | Floci | Low-memory AWS API emulator running inside the cluster. |
| **GitOps Engine** | Argo CD | Declarative GitOps reconciliation using the App-of-Apps pattern. |
| **CI Automation** | GitHub Actions | Builds Docker images and updates manifest tags in GitOps repo. |
| **Observability** | Prometheus + Loki + Tempo + Grafana | Metrics, logs, traces unified under OpenTelemetry. |
| **FinOps** | OpenCost | In-cluster compute cost allocation and spend attribution per namespace. |
| **Developer Portal** | MkDocs (Material) | Self-service docs hosted on GitHub Pages (zero cluster RAM). |

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/<YOUR_USERNAME>/FrugalZeus.git
cd FrugalZeus

# 2. Bootstrap the entire platform
make bootstrap

# 3. Open developer port-forwards
make ports

# 4. Run endpoint smoke tests
make test
```

---

## Architecture Diagram

```mermaid
graph TB
    subgraph "Single Linux VM - k3s"
        subgraph "argocd namespace"
            ArgoCD["Argo CD<br/>GitOps Engine"]
        end
        subgraph "platform-infra namespace"
            Floci["Floci<br/>AWS Emulator :4566"]
        end
        subgraph "monitoring namespace"
            Prom["Prometheus"]
            Grafana["Grafana"]
            Loki["Loki - monolithic"]
            Tempo["Tempo - monolithic"]
            Promtail["Promtail"]
        end
        subgraph "opencost namespace"
            OC["OpenCost"]
        end
        subgraph "tenant-team-alpha namespace"
            App["FastAPI Microservice<br/>OTel auto-instrumented"]
            Quota["ResourceQuota"]
            Limits["LimitRange"]
            NetPol["NetworkPolicy"]
        end
    end

    TF["Terraform<br/>runs on VM host"] -->|"port-forward :4566<br/>create S3 bucket"| Floci
    GH["GitHub Actions<br/>CI Pipeline"] -->|"push image to Docker Hub<br/>update tag in repo"| GitRepo["platform-gitops<br/>GitHub Repo"]
    GitRepo -->|"App-of-Apps sync"| ArgoCD
    ArgoCD -->|"reconcile"| Floci
    ArgoCD -->|"reconcile"| Prom
    ArgoCD -->|"reconcile"| Loki
    ArgoCD -->|"reconcile"| Tempo
    ArgoCD -->|"reconcile"| OC
    ArgoCD -->|"reconcile"| App
    App -->|"write objects"| Floci
    App -->|"OTLP HTTP traces"| Tempo
    App -->|":9464 /metrics"| Prom
    Prom -->|"scrape ServiceMonitor"| App
    Promtail -->|"ship logs"| Loki
    OC -->|"read metrics"| Prom
    Grafana -->|"query metrics"| Prom
    Grafana -->|"query logs"| Loki
    Grafana -->|"query traces"| Tempo
```

---

## Developer Commands

```bash
make help       # List available make commands
make bootstrap  # Install k3s, Argo CD, Floci, apply Terraform
make ports      # Port-forward Grafana, Argo CD, App, OpenCost
make status     # Show nodes, Argo CD applications, and pod status
make test       # Smoke test /health, /upload, /list, /metrics
make password   # Output Argo CD initial admin password
make clean      # Uninstall k3s completely
```
