#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "      FrugalZeus Platform Bootstrap       "
echo "=========================================="
echo ""
echo "Select Kubernetes Environment Option:"
echo "  1) Use existing Kubernetes cluster"
echo "  2) Install / provision local k3s cluster (default)"
echo ""

read -rp "Enter choice [1 or 2] (default: 2): " CHOICE
CHOICE=${CHOICE:-2}

if [ "$CHOICE" = "1" ]; then
    echo "=== Step 1: Using Existing Kubernetes Cluster ==="
    if ! kubectl cluster-info > /dev/null 2>&1; then
        echo "Error: Cannot connect to Kubernetes cluster. Check kubeconfig."
        exit 1
    fi
    echo "✓ Connected to existing cluster: $(kubectl config current-context)"
else
    echo "=== Step 1: Install k3s ==="
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown "$(id -u):$(id -g)" ~/.kube/config
    kubectl wait --for=condition=Ready node --all --timeout=120s
    echo "✓ k3s is running. Node IP: $(hostname -I | awk '{print $1}')"
fi

# ===========================================================================
echo ""
echo "=== Step 2: Install Argo CD ==="
kubectl create namespace argocd 2>/dev/null || true

# Use --server-side to avoid CRD annotation-too-long error (>262144 bytes)
echo "Applying Argo CD manifests (server-side apply — avoids CRD annotation limit)..."
kubectl apply --server-side --force-conflicts \
    -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for argocd-server to become Available..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=240s

# Remove Argo CD's own NetworkPolicies — they block external access in some setups
echo "Removing Argo CD's restrictive internal NetworkPolicies..."
kubectl delete networkpolicy --all -n argocd 2>/dev/null || true

# Enable insecure (HTTP) mode so we can access via plain NodePort
echo "Enabling Argo CD HTTP insecure mode..."
kubectl patch cm argocd-cmd-params-cm -n argocd \
    --type merge -p '{"data":{"server.insecure":"true"}}'

# Expose argocd-server on NodePort 30080 (HTTP)
echo "Patching argocd-server to NodePort 30080..."
kubectl patch svc argocd-server -n argocd -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name": "http",  "port": 80,  "targetPort": 8080, "nodePort": 30080},
      {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}
    ]
  }
}'

kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=120s
echo "✓ Argo CD: http://$(hostname -I | awk '{print $1}'):30080"

# ===========================================================================
echo ""
echo "=== Step 3: Apply GitOps Root App & All Infrastructure Applications ==="
kubectl apply -f platform-gitops/root-app.yaml
kubectl apply --server-side --force-conflicts -n argocd -f platform-gitops/infrastructure/
echo "✓ Argo CD Application manifests submitted. Sync starting..."

# ===========================================================================
echo ""
echo "=== Step 4: Wait for Floci (Sync Wave 1 — required for Terraform) ==="
FLOCI_READY=false
for i in $(seq 1 40); do
    if kubectl wait --for=condition=ready pod -l app=floci -n platform-infra --timeout=10s 2>/dev/null; then
        FLOCI_READY=true
        break
    fi
    echo "  Waiting for Floci... ($i/40)"
    sleep 10
done
if [ "$FLOCI_READY" = "true" ]; then
    echo "✓ Floci is running."
else
    echo "! Floci not ready after 400s — continuing (Terraform may fail)."
fi

# ===========================================================================
echo ""
echo "=== Step 5: Run Terraform ==="
if [ -d "terraform" ]; then
    kubectl port-forward svc/floci -n platform-infra 4566:4566 &
    PF_PID=$!
    sleep 4
    cd terraform
    terraform init -input=false
    terraform apply -auto-approve -input=false
    cd ..
    kill $PF_PID 2>/dev/null || true
    echo "✓ Terraform applied."
else
    echo "  No terraform/ directory found, skipping."
fi

# ===========================================================================
echo ""
echo "=== Step 6: Wait for Monitoring (Sync Wave 2) & Patch NodePorts ==="
echo "Waiting for Grafana pod (this takes 2-5 min for chart download)..."
GRAFANA_READY=false
for i in $(seq 1 36); do
    if kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=grafana" \
        -n monitoring --timeout=10s 2>/dev/null; then
        GRAFANA_READY=true
        break
    fi
    echo "  Waiting for Grafana... ($i/36)"
    sleep 10
done

if [ "$GRAFANA_READY" = "true" ]; then
    echo "✓ Grafana pod is ready. Patching service to NodePort 30000..."
    GRAFANA_SVC=$(kubectl get svc -n monitoring -l "app.kubernetes.io/name=grafana" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$GRAFANA_SVC" ]; then
        kubectl patch svc "$GRAFANA_SVC" -n monitoring -p '{
          "spec": {
            "type": "NodePort",
            "ports": [{"port": 80, "targetPort": 3000, "nodePort": 30000}]
          }
        }'
        echo "✓ Grafana NodePort 30000 active."
    fi
else
    echo "! Grafana not ready in time. Run 'make patch-nodeports' after sync completes."
fi

# ===========================================================================
echo ""
echo "=== Step 7: Wait for OpenCost (Sync Wave 4) & Patch NodePort ==="
OPENCOST_READY=false
for i in $(seq 1 30); do
    if kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=opencost" \
        -n opencost --timeout=10s 2>/dev/null; then
        OPENCOST_READY=true
        break
    fi
    echo "  Waiting for OpenCost... ($i/30)"
    sleep 10
done

if [ "$OPENCOST_READY" = "true" ]; then
    echo "✓ OpenCost pod is ready. Patching service to NodePort 30903..."
    OC_SVC=$(kubectl get svc -n opencost -l "app.kubernetes.io/name=opencost" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$OC_SVC" ]; then
        kubectl patch svc "$OC_SVC" -n opencost -p '{
          "spec": {
            "type": "NodePort",
            "ports": [{"port": 9003, "targetPort": 9003, "nodePort": 30903}]
          }
        }'
        echo "✓ OpenCost NodePort 30903 active."
    fi
else
    echo "! OpenCost not ready in time. Run 'make patch-nodeports' after sync completes."
fi

# ===========================================================================
echo ""
echo "=== Step 8: Wait for Guestbook (Sync Wave 5) ==="
for i in $(seq 1 20); do
    if kubectl get svc guestbook-ui-nodeport -n tenant-guestbook 2>/dev/null; then
        echo "✓ Guestbook NodePort 30800 active."
        break
    fi
    echo "  Waiting for guestbook-ui-nodeport service... ($i/20)"
    sleep 10
done

# ===========================================================================
NODE_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo '<NODE-IP>')
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo '<pending>')

echo ""
echo "=========================================="
echo "   ✓ Platform Bootstrap Complete!         "
echo "=========================================="
echo ""
echo "  NodePort Endpoints (direct access — no port-forward):"
echo "  ┌────────────┬──────────────────────────────────────────────┐"
echo "  │ Grafana    │ http://${NODE_IP}:30000  (admin/platform-admin)│"
echo "  │ Argo CD    │ http://${NODE_IP}:30080  (admin/${ARGO_PASSWORD})│"
echo "  │ Guestbook  │ http://${NODE_IP}:30800                       │"
echo "  │ OpenCost   │ http://${NODE_IP}:30903                       │"
echo "  └────────────┴──────────────────────────────────────────────┘"
echo ""
echo "  To verify NodePorts: make nodeports"
echo "  Localhost forwards: make ports  (3000/8080/8000/9003)"
echo ""
