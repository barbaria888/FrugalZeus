.PHONY: bootstrap ports status password test clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Full platform setup: k3s -> Argo CD -> Floci -> Terraform
	bash k3s/bootstrap.sh

ports: ## Open all service UIs (single command)
	@echo ""
	@echo "  Grafana:   http://localhost:3000   (admin / platform-admin)"
	@echo "  Argo CD:   https://localhost:8080  (admin / $$($(MAKE) -s password))"
	@echo "  App:       http://localhost:8000"
	@echo "  OpenCost:  http://localhost:9003"
	@echo ""
	@kubectl port-forward svc/prometheus-grafana   -n monitoring         3000:80   > /dev/null 2>&1 &
	@kubectl port-forward svc/argocd-server         -n argocd            8080:443  > /dev/null 2>&1 &
	@kubectl port-forward svc/team-alpha-svc        -n tenant-team-alpha 8000:8000 > /dev/null 2>&1 &
	@kubectl port-forward svc/opencost              -n opencost          9003:9003 > /dev/null 2>&1 &
	@echo "All services forwarded. Press Ctrl+C to stop."
	@wait

password: ## Get Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

status: ## Show platform health: nodes, apps, pods
	@echo "=== Nodes ==="
	@kubectl get nodes
	@echo ""
	@echo "=== Argo CD Applications ==="
	@kubectl get applications -n argocd
	@echo ""
	@echo "=== Pods (all namespaces) ==="
	@kubectl get pods -A

test: ## Smoke test the microservice endpoints
	@echo "Testing /health..."
	@curl -sf http://localhost:8000/health | jq .
	@echo "Testing /upload..."
	@curl -sf -X POST http://localhost:8000/upload/smoke-test | jq .
	@echo "Testing /list..."
	@curl -sf http://localhost:8000/list | jq .
	@echo "Testing /metrics (OTel Prometheus exporter)..."
	@curl -sf http://localhost:9464/metrics | head -5
	@echo ""
	@echo "✓ All smoke tests passed"

clean: ## Tear down k3s completely
	/usr/local/bin/k3s-uninstall.sh
