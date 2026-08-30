# FinOps & Cost Attribution

This document outlines the platform's financial operations (FinOps) architecture, designed to provide deterministic, real-time cost attribution at the namespace boundary.

## Core Architecture

The platform integrates **OpenCost** directly into the control plane to continuously calculate the monetary value of compute consumption.

- **Data Source**: OpenCost relies on Prometheus as its TSDB (Time Series Database). It queries `container_cpu_usage_seconds_total` and `container_memory_working_set_bytes` to determine active consumption.
- **Cost Allocation Model**: Resources are attributed based on the Kubernetes namespace. This aligns infrastructure spend directly with the tenant teams operating those namespaces, enabling strict showback/chargeback models.
- **Zero-Configuration UI**: The OpenCost UI is exposed on NodePort `30903` (`http://localhost:30903`), providing immediate, self-service access to cost reports without requiring secondary BI tools.

## Strategic Capabilities

1. **Granular Showback**: Expose the true cost of microservices to the engineering teams developing them, fostering a culture of resource optimization.
2. **Idle Cost Identification**: Isolate the delta between provisioned resources (Requests/Limits) and actual consumption, enabling automated rightsizing recommendations.
3. **Multi-Tenant Accountability**: By correlating OpenCost data with Kustomize-enforced `ResourceQuotas`, the platform architect can enforce hard financial limits on tenant environments.
