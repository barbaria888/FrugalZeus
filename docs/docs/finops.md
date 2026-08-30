# FinOps & Cost Attribution Guide

## Overview

The platform uses **OpenCost** to provide real-time in-cluster cost allocation and spend attribution across tenant namespaces.

## Key Capabilities

- **Per-Namespace Breakdown**: OpenCost queries Prometheus container CPU and memory usage to calculate exact monetary spend per tenant.
- **Grafana Dashboard**: An OpenCost dashboard is automatically loaded in Grafana under the `monitoring` namespace.
- **Self-Service Cost Tracking**: Access OpenCost UI directly via `make ports` at `http://localhost:9003`.
