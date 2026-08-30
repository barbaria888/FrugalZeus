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
        echo "Error: Unable to connect to your existing Kubernetes cluster. Please verify your kubeconfig."
        exit 1
    fi
    echo "✓ Connected to existing cluster."
else
    echo "=== Step 1: Install k3s Cluster ==="
    # service-node-port-range extended to 30000-32767 (default) — ports 30000-30903 are all valid
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null || true
    sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    kubectl wait --for=condition=Ready node --all --timeout=120s
    echo "✓ k3s cluster is running."
fi

echo ""
echo "=== Step 2: Install & Configure Argo CD ==="
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s

echo "Configuring Argo CD server.insecure: 'true'..."
kubectl patch cm argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'

echo "Exposing Argo CD on NodePort 30080 (HTTP)..."
kubectl patch svc argocd-server -n argocd -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name": "http",  "port": 80,  "targetPort": 8080, "nodePort": 30080},
      {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}
    ]
  }
}'

echo "Restarting argocd-server to pick up insecure flag..."
kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=120s
echo "✓ Argo CD running at NodePort 30080 (HTTP, insecure)."

echo ""
echo "=== Step 3: Apply GitOps Root Application & Infrastructure Apps ==="
kubectl apply -f platform-gitops/root-app.yaml
# Apply all infra apps directly so Argo CD begins syncing immediately
kubectl apply -n argocd -f platform-gitops/infrastructure/

echo ""
echo "=== Step 4: Wait for Floci (Sync Wave 1) ==="
echo "(Argo CD is syncing infrastructure in the background. Floci required for Terraform.)"
for i in $(seq 1 30); do
    if kubectl wait --for=condition=ready pod -l app=floci -n platform-infra --timeout=20s 2>/dev/null; then
        break
    fi
    echo "  Waiting for Floci pod... attempt $i/30"
    sleep 5
done
echo "✓ Floci is running."

echo ""
echo "=== Step 5: Run Terraform via Floci Port-Forward ==="
kubectl port-forward svc/floci -n platform-infra 4566:4566 &
PF_PID=$!
sleep 4

if [ -d "terraform" ]; then
    cd terraform
    terraform init -input=false
    terraform apply -auto-approve -input=false
    cd ..
fi
kill $PF_PID 2>/dev/null || true

ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo '<pending>')

echo ""
echo "=========================================="
echo "   ✓ Platform Bootstrap Complete!         "
echo "=========================================="
echo ""
echo "  NodePort Endpoints (direct, no port-forward needed):"
echo "  ┌──────────────┬────────────────────────────────────────────────────────┐"
echo "  │ Service      │ URL                                                    │"
echo "  ├──────────────┼────────────────────────────────────────────────────────┤"
echo "  │ Grafana      │ http://<NODE-IP>:30000   (admin / platform-admin)       │"
echo "  │ Argo CD      │ http://<NODE-IP>:30080   (admin / ${ARGO_PASSWORD})     │"
echo "  │ Guestbook    │ http://<NODE-IP>:30800                                  │"
echo "  │ OpenCost     │ http://<NODE-IP>:30903                                  │"
echo "  └──────────────┴────────────────────────────────────────────────────────┘"
echo ""
echo "  Replace <NODE-IP> with: $(hostname -I | awk '{print $1}' 2>/dev/null || echo 'your VM IP')"
echo ""
echo "  NOTE: Grafana, Guestbook, and OpenCost NodePorts are deployed by Argo CD."
echo "  Run 'make sync-wait' to wait for them to become Healthy, then access directly."
echo ""
echo "  Alternatively, run 'make ports' for localhost port-forwards on 3000/8080/8000/9003."
echo ""
