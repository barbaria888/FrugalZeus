# Team Onboarding Guide

To onboard a new tenant team (e.g., `team-beta`), follow these simple steps:

## Step-by-Step Onboarding

1. **Copy the Base Overlay Template**:
   ```bash
   cp -r platform-gitops/tenants/team-alpha platform-gitops/tenants/team-beta
   ```

2. **Update Kustomization Configuration**:
   In `platform-gitops/tenants/team-beta/kustomization.yaml`, update the namespace:
   ```yaml
   namespace: tenant-team-beta
   commonLabels:
     team: beta
   ```

3. **Register the New Application in Argo CD**:
   Create `platform-gitops/infrastructure/team-beta.yaml`:
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
   ```

4. **Commit & Push**:
   ```bash
   git add platform-gitops/
   git commit -m "feat: onboard team-beta tenant"
   git push
   ```
   Argo CD will automatically provision the namespace, resource quotas, limit ranges, network policies, service monitors, and application workloads.
