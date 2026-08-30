.PHONY: bootstrap ports status password test observe nodeports sync-wait clean help

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

observe: ## Print all NodePort and port-forward endpoints with credentials
	@NODE_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo 'YOUR-VM-IP'); \
	ARGO_PASS=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "run: make password"); \
	echo ""; \
	echo "═══════════════════════════════════════════════════════════════"; \
	echo "           FrugalZeus Platform Endpoints"; \
	echo "═══════════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "  NodePort Access (direct, from the VM or host — no port-forward):"; \
	echo "  ┌──────────────┬─────────────────────────────────────────────┐"; \
	echo "  │ Grafana      │ http://$$NODE_IP:30000  (admin/platform-admin)│"; \
	echo "  │ Argo CD      │ http://$$NODE_IP:30080  (admin/$$ARGO_PASS)"; \
	echo "  │ Guestbook    │ http://$$NODE_IP:30800                       │"; \
	echo "  │ OpenCost     │ http://$$NODE_IP:30903                       │"; \
	echo "  └──────────────┴─────────────────────────────────────────────┘"; \
	echo ""; \
	echo "  Localhost Access (via 'make ports' port-forwards):"; \
	echo "  ┌──────────────┬─────────────────────────────────────────────┐"; \
	echo "  │ Grafana      │ http://localhost:3000   (admin/platform-admin)│"; \
	echo "  │ Argo CD      │ http://localhost:8080   (admin/$$ARGO_PASS)"; \
	echo "  │ Guestbook    │ http://localhost:8000                        │"; \
	echo "  │ OpenCost     │ http://localhost:9003                        │"; \
	echo "  └──────────────┴─────────────────────────────────────────────┘"; \
	echo ""; \
	echo "  Grafana Datasources (pre-wired, no manual setup):"; \
	echo "    Prometheus  -> metrics (ServiceMonitor scraping)"; \
	echo "    Loki        -> logs    (Promtail container collection)"; \
	echo "    Tempo       -> traces  (OTLP from instrumented apps)"; \
	echo ""; \
	echo "═══════════════════════════════════════════════════════════════"

nodeports: ## Show live NodePort status for all platform services
	@echo "=== NodePort Services ==="
	@echo ""
	@NODE_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo 'UNKNOWN'); \
	echo "Node IP: $$NODE_IP"; echo ""; \
	echo "Grafana (30000):"; \
	kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='  {.items[0].spec.type} -> {.items[0].spec.ports[0].nodePort}{"\n"}' 2>/dev/null || echo "  NOT SYNCED"; \
	echo "Argo CD (30080):"; \
	kubectl get svc argocd-server -n argocd -o jsonpath='  {.spec.type} -> {.spec.ports[0].nodePort}{"\n"}' 2>/dev/null || echo "  NOT FOUND"; \
	echo "Guestbook (30800):"; \
	kubectl get svc guestbook-ui-nodeport -n tenant-guestbook -o jsonpath='  {.spec.type} -> {.spec.ports[0].nodePort}{"\n"}' 2>/dev/null || echo "  NOT SYNCED"; \
	echo "OpenCost (30903):"; \
	kubectl get svc -n opencost -l app.kubernetes.io/name=opencost -o jsonpath='  {.items[0].spec.type} -> {.items[0].spec.ports[0].nodePort}{"\n"}' 2>/dev/null || echo "  NOT SYNCED"

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
