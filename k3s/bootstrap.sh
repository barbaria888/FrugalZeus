#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "      Flagship Platform Bootstrap         "
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
        echo "Error: Unable to connect to your existing Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    echo "✓ Connected to existing cluster."
else
    echo "=== Step 1: Install k3s Cluster ==="
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --kube-apiserver-arg=service-node-port-range=1-65535" sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null || true
    sudo chown $(id -u):$(id -g) ~/.kube/config 2>/dev/null || true
    kubectl wait --for=condition=Ready node --all --timeout=120s
    echo "✓ k3s cluster is running (Traefik included)."
fi

echo "=== Step 2: Install & Configure Argo CD ==="
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Setting Argo CD server.insecure: 'true'..."
kubectl patch cm argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || true

echo "Exposing Argo CD Server on NodePort 30080..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "nodePort": 30080}, {"name": "https", "port": 443}]}}' 2>/dev/null || true

kubectl rollout restart deployment argocd-server -n argocd 2>/dev/null || true
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s
echo "✓ Argo CD is running in insecure HTTP mode on NodePort 30080."

echo "=== Step 3: Apply Root App & Platform Infrastructure Apps ==="
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

echo ""
echo "=========================================="
echo "   ✓ Platform Bootstrap Complete!         "
echo "=========================================="
echo "  NodePort Endpoints & Credentials:"
echo "  - Grafana:   http://localhost:30000   (admin / platform-admin)"
echo "  - Argo CD:   http://localhost:30080   (admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '<password>'))"
echo "  - App:       http://localhost:30800"
echo "  - OpenCost:  http://localhost:30903"
echo ""
echo "Run 'make ports' to forward 3000, 8080, 8000, 9003 locally."
