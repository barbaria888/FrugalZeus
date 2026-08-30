#!/bin/bash
set -euo pipefail

echo "=== Step 1: Install k3s ==="
# Traefik is kept enabled (k3s default) — used for Ingress capability
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl wait --for=condition=Ready node --all --timeout=120s
echo "✓ k3s is running (Traefik ingress controller included)"

echo "=== Step 2: Install Argo CD ==="
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=180s
echo "✓ Argo CD is running"

echo "=== Step 3: Apply root App-of-Apps ==="
kubectl apply -f platform-gitops/root-app.yaml

echo "=== Step 4: Wait for Floci to be Ready (Sync Wave 1) ==="
kubectl wait --for=condition=ready pod -l app=floci -n platform-infra --timeout=120s
echo "✓ Floci is running"

echo "=== Step 5: Port-forward Floci & run Terraform ==="
kubectl port-forward svc/floci -n platform-infra 4566:4566 &
PF_PID=$!
sleep 3

cd terraform
terraform init
terraform apply -auto-approve
cd ..

kill $PF_PID 2>/dev/null || true

echo ""
echo "=== ✓ Platform bootstrap complete ==="
echo "Run 'make ports' to access all services."
echo "Run 'make password' to get the Argo CD admin password."
