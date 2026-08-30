# Tenant Onboarding Contract

This document defines the strict, automated procedure for provisioning a new tenant environment (e.g., `team-beta`). The platform enforces a declarative, GitOps-driven onboarding flow to guarantee consistency and security compliance.

## The Onboarding Procedure

Tenant environments are stamped out using immutable Kustomize base overlays. 

### 1. Instantiate the Tenant Manifests

Duplicate the verified tenant baseline configuration. This ensures the new tenant inherits all foundational guardrails (`NetworkPolicy`, `ResourceQuota`, `LimitRange`).

```bash
cp -r platform-gitops/tenants/team-alpha platform-gitops/tenants/team-beta
```

### 2. Configure Tenant Overlays

Modify the `kustomization.yaml` within the new tenant directory (`platform-gitops/tenants/team-beta/kustomization.yaml`) to inject tenant-specific metadata.

```yaml
namespace: tenant-team-beta
commonLabels:
  team: beta
  platform.io/tenant: "true"
```

### 3. Define the Argo CD Application

Declare the new tenant configuration as an Argo CD `Application` resource. Create `platform-gitops/infrastructure/team-beta.yaml`.

*Crucial: Ensure `ServerSideApply=true` and `CreateNamespace=true` are defined in `syncOptions` to bypass client-side validation limits and ensure the destination namespace exists prior to resource injection.*

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-beta
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  project: default
  source:
    repoURL: https://github.com/barbaria888/FrugalZeus.git
    targetRevision: main
    path: platform-gitops/tenants/team-beta
  destination:
    server: https://kubernetes.default.svc
    namespace: tenant-team-beta
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 4. Execute GitOps Reconciliation

Commit the declarative state changes to the repository.

```bash
git add platform-gitops/
git commit -m "feat(platform): provision tenant-team-beta environment"
git push
```

**Expected Outcome**: Argo CD detects the repository mutation, evaluates the sync-waves, and deterministically provisions the `tenant-team-beta` namespace, enforces the security policies, and schedules the defined workloads.
