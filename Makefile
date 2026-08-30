.PHONY: bootstrap ports status password test observe sync-wait clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Full platform setup: Cluster -> Argo CD -> GitOps -> Floci -> Terraform
	bash k3s/bootstrap.sh

ports: ## Open verified local port-forwards to all service UIs (Grafana, Argo CD, Guestbook, OpenCost)
	bash scripts/port-forward.sh

password: ## Output Argo CD initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Admin secret not found in namespace 'argocd'"

sync-wait: ## Wait for all Argo CD applications to reach Synced+Healthy state (up to 10 minutes)
	@echo "Waiting for all Argo CD applications to sync..."
	@kubectl wait applications --all -n argocd \
		--for=jsonpath='{.status.health.status}'=Healthy \
		--timeout=600s 2>/dev/null || true
	@echo ""
	@kubectl get applications -n argocd -o wide

status: ## Show platform health: nodes, Argo CD applications, and pod statuses
	@echo "=== 1. Kubernetes Nodes ==="
	@kubectl get nodes -o wide 2>/dev/null || echo "Unable to query nodes."
	@echo ""
	@echo "=== 2. Argo CD Applications ==="
	@kubectl get applications -n argocd -o wide 2>/dev/null || echo "No Argo CD applications found in namespace 'argocd'."
	@echo ""
	@echo "=== 3. Platform Pods (All Namespaces) ==="
	@kubectl get pods -A 2>/dev/null || echo "Unable to query pods."
	@echo ""
	@echo "=== 4. Platform Services ==="
	@kubectl get svc -n monitoring -n argocd -n opencost -n tenant-guestbook 2>/dev/null || true

observe: ## Print all observability URLs (requires 'make ports' to be running)
	@echo ""
	@echo "FrugalZeus Observability Endpoints"
	@echo "==================================="
	@echo ""
	@echo "  Grafana (Metrics, Logs, Traces)"
	@echo "    http://localhost:3000"
	@echo "    Login: admin / platform-admin"
	@echo ""
	@echo "  Pre-configured Dashboards:"
	@echo "    Kubernetes / Compute Resources / Namespace"
	@echo "    Kubernetes / Compute Resources / Pod"
	@echo "    Node Exporter / Full"
	@echo ""
	@echo "  Pre-wired Datasources:"
	@echo "    Prometheus  -> metrics scraping from all platform.io/tenant=true services"
	@echo "    Loki        -> logs from all pods via Promtail"
	@echo "    Tempo       -> distributed traces from OTLP-instrumented services"
	@echo ""
	@echo "  OpenCost (FinOps)"
	@echo "    http://localhost:9003"
	@echo "    Namespace cost breakdown: tenant-guestbook, monitoring, opencost"
	@echo ""
	@echo "  Argo CD (GitOps)"
	@echo "    http://localhost:8080"
	@PASS=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "see 'make password'"); \
	echo "    Login: admin / $$PASS"
	@echo ""
	@echo "  Guestbook App"
	@echo "    http://localhost:8000"
	@echo ""

test: ## Smoke test guestbook and platform observability endpoints (requires 'make ports')
	@echo "=== Testing Guestbook App ==="
	@curl -sf -o /dev/null -w "Guestbook: HTTP %{http_code}\n" http://localhost:8000 || (echo "ERROR: Guestbook not reachable. Is 'make ports' running?" && exit 1)
	@echo ""
	@echo "=== Testing Grafana ==="
	@curl -sf -o /dev/null -w "Grafana: HTTP %{http_code}\n" http://localhost:3000/api/health || (echo "ERROR: Grafana not reachable." && exit 1)
	@echo ""
	@echo "=== Testing Prometheus (via Grafana datasource) ==="
	@curl -sf -o /dev/null -w "Prometheus: HTTP %{http_code}\n" \
		-u admin:platform-admin \
		"http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" || true
	@echo ""
	@echo "=== Testing OpenCost ==="
	@curl -sf -o /dev/null -w "OpenCost: HTTP %{http_code}\n" http://localhost:9003 || (echo "ERROR: OpenCost not reachable." && exit 1)
	@echo ""
	@echo "✓ Platform smoke tests complete. Run 'make observe' for full endpoint reference."

clean: ## Tear down k3s completely (destructive)
	/usr/local/bin/k3s-uninstall.sh 2>/dev/null || echo "k3s uninstall script not found."
