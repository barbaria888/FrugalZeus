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
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null || true
    sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    kubectl wait --for=condition=Ready node --all --timeout=120s
    echo "✓ k3s cluster is running."
fi

echo "=== Step 2: Install & Configure Argo CD ==="
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Configuring Argo CD server.insecure: 'true'..."
kubectl patch cm argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || true
kubectl rollout restart deployment argocd-server -n argocd 2>/dev/null || true
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s
echo "✓ Argo CD is running (insecure HTTP enabled)."

echo "=== Step 3: Apply GitOps Root Application & Infrastructure ==="
kubectl apply -f platform-gitops/root-app.yaml
kubectl apply -f platform-gitops/infrastructure/ -n argocd

echo "=== Step 4: Wait for Floci to be Ready (Sync Wave 1) ==="
kubectl wait --for=condition=ready pod -l app=floci -n platform-infra --timeout=180s 2>/dev/null || true
echo "✓ Floci is running"

echo "=== Step 5: Port-forward Floci & Run Terraform ==="
kubectl port-forward svc/floci -n platform-infra 4566:4566 &
PF_PID=$!
sleep 3

if [ -d "terraform" ]; then
    cd terraform
    terraform init
    terraform apply -auto-approve
    cd ..
fi

kill $PF_PID 2>/dev/null || true

ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '<generated-on-sync>')

echo ""
echo "=========================================="
echo "   ✓ Platform Bootstrap Complete!         "
echo "=========================================="
echo ""
echo "Start developer access with: make ports"
echo ""
echo "Forwarded Endpoints:"
echo "  • Grafana:   http://localhost:3000   (admin / platform-admin)"
echo "  • Argo CD:   http://localhost:8080   (admin / ${ARGO_PASSWORD})"
echo "  • App:       http://localhost:8000"
echo "  • OpenCost:  http://localhost:9003"
echo ""
