.PHONY: bootstrap apply-apps patch-nodeports ports status password test observe nodeports sync-wait clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Full platform setup: Cluster -> Argo CD -> GitOps -> Floci -> Terraform
	bash k3s/bootstrap.sh

apply-apps: ## Apply GitOps root app + all infrastructure Application manifests to Argo CD
	@echo "Applying Argo CD root application..."
	kubectl apply -f platform-gitops/root-app.yaml
	@echo "Applying all infrastructure Argo CD Application manifests (server-side)..."
	kubectl apply --server-side --force-conflicts -n argocd -f platform-gitops/infrastructure/
	@echo ""
	@echo "✓ Applications submitted. Run 'make sync-wait' to wait for Healthy state."

patch-nodeports: ## Force-patch all services to NodePort (run after 'make sync-wait')
	@echo "=== Patching Services to NodePort ==="
	@echo ""
	@echo "Patching Argo CD server -> NodePort 30080..."
	@kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":8080,"nodePort":30080},{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}' 2>/dev/null && echo "  ✓ Argo CD: 30080" || echo "  ✗ argocd-server not found"
	@echo ""
	@echo "Patching Grafana -> NodePort 30000..."
	@GRAFANA_SVC=$$(kubectl get svc -n monitoring -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$GRAFANA_SVC" ]; then \
		kubectl patch svc "$$GRAFANA_SVC" -n monitoring -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":3000,"nodePort":30000}]}}' && echo "  ✓ Grafana: 30000"; \
	else echo "  ✗ Grafana service not found (still syncing?)"; fi
	@echo ""
	@echo "Patching OpenCost -> NodePort 30903..."
	@OC_SVC=$$(kubectl get svc -n opencost -l "app.kubernetes.io/name=opencost" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -n "$$OC_SVC" ]; then \
		kubectl patch svc "$$OC_SVC" -n opencost -p '{"spec":{"type":"NodePort","ports":[{"port":9003,"targetPort":9003,"nodePort":30903}]}}' && echo "  ✓ OpenCost: 30903"; \
	else echo "  ✗ OpenCost service not found (still syncing?)"; fi
	@echo ""
	@echo "Checking guestbook-ui-nodeport service (created by Argo CD guestbook-nodeport app)..."
	@kubectl get svc guestbook-ui-nodeport -n tenant-guestbook 2>/dev/null && echo "  ✓ Guestbook NodePort 30800 exists" || echo "  ✗ guestbook-ui-nodeport not found (check guestbook-nodeport Argo CD app)"
	@echo ""
	@make nodeports

sync-wait: ## Wait for all Argo CD apps to reach Synced+Healthy (up to 10 min)
	@echo "Current Argo CD application state:"
	@kubectl get applications -n argocd 2>/dev/null || echo "  No applications found. Run 'make apply-apps' first."
	@echo ""
	@echo "Waiting for all applications to become Healthy (timeout: 600s)..."
	@kubectl wait applications --all -n argocd \
		--for=jsonpath='{.status.health.status}'=Healthy \
		--timeout=600s 2>/dev/null && echo "✓ All applications are Healthy." || \
		(echo ""; echo "Some applications may still be syncing. Current state:"; kubectl get applications -n argocd 2>/dev/null)

ports: ## Open verified local port-forwards to all service UIs (Grafana, Argo CD, Guestbook, OpenCost)
	bash scripts/port-forward.sh

password: ## Output Argo CD initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Admin secret not found in namespace 'argocd'"

status: ## Show platform health: nodes, Argo CD applications, pods, and services
	@echo "=== 1. Kubernetes Nodes ==="
	@kubectl get nodes -o wide 2>/dev/null || echo "Unable to query nodes."
	@echo ""
	@echo "=== 2. Argo CD Applications ==="
	@kubectl get applications -n argocd 2>/dev/null || echo "No Argo CD applications found — run 'make apply-apps'."
	@echo ""
	@echo "=== 3. Platform Pods (All Namespaces) ==="
	@kubectl get pods -A 2>/dev/null || echo "Unable to query pods."
	@echo ""
	@echo "=== 4. Key Services ==="
	@for ns in monitoring argocd opencost tenant-guestbook; do \
		echo "--- namespace: $$ns ---"; \
		kubectl get svc -n $$ns 2>/dev/null || echo "  (not created yet)"; \
	done

observe: ## Print all NodePort and localhost port-forward endpoints with credentials
	@NODE_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo 'YOUR-VM-IP'); \
	ARGO_PASS=$$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "run: make password"); \
	echo ""; \
	echo "═══════════════════════════════════════════════════════════════════"; \
	echo "              FrugalZeus Platform Endpoints"; \
	echo "═══════════════════════════════════════════════════════════════════"; \
	echo ""; \
	echo "  NodePort (direct access from host/VM, no port-forward needed):"; \
	echo "    Grafana   ->  http://$$NODE_IP:30000   (admin / platform-admin)"; \
	echo "    Argo CD   ->  http://$$NODE_IP:30080   (admin / $$ARGO_PASS)"; \
	echo "    Guestbook ->  http://$$NODE_IP:30800"; \
	echo "    OpenCost  ->  http://$$NODE_IP:30903"; \
	echo ""; \
	echo "  Localhost (via 'make ports' port-forwards):"; \
	echo "    Grafana   ->  http://localhost:3000    (admin / platform-admin)"; \
	echo "    Argo CD   ->  http://localhost:8080    (admin / $$ARGO_PASS)"; \
	echo "    Guestbook ->  http://localhost:8000"; \
	echo "    OpenCost  ->  http://localhost:9003"; \
	echo ""; \
	echo "  Grafana Datasources (auto-configured, no manual setup):"; \
	echo "    Prometheus  ->  Metrics (ServiceMonitor scraping)"; \
	echo "    Loki        ->  Logs    (Promtail container collection)"; \
	echo "    Tempo       ->  Traces  (OTLP from instrumented apps)"; \
	echo ""; \
	echo "═══════════════════════════════════════════════════════════════════"

nodeports: ## Verify live NodePort assignments on the cluster
	@echo "=== Live NodePort Status ==="
	@NODE_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo 'UNKNOWN'); \
	echo "Node IP: $$NODE_IP"; \
	echo ""; \
	printf "%-12s %-8s %-12s\n" "Service" "Port" "Status"; \
	printf "%-12s %-8s %-12s\n" "-------" "----" "------"; \
	GRAFANA_NP=$$(kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.ports[?(@.nodePort)].nodePort}' 2>/dev/null || echo ""); \
	[ -n "$$GRAFANA_NP" ] && printf "%-12s %-8s %-12s\n" "Grafana" "30000" "✓ http://$$NODE_IP:$$GRAFANA_NP" || printf "%-12s %-8s %-12s\n" "Grafana" "30000" "NOT SYNCED"; \
	ARGOCD_NP=$$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo ""); \
	[ -n "$$ARGOCD_NP" ] && printf "%-12s %-8s %-12s\n" "Argo CD" "30080" "✓ http://$$NODE_IP:$$ARGOCD_NP" || printf "%-12s %-8s %-12s\n" "Argo CD" "30080" "NOT PATCHED"; \
	GB_NP=$$(kubectl get svc guestbook-ui-nodeport -n tenant-guestbook -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo ""); \
	[ -n "$$GB_NP" ] && printf "%-12s %-8s %-12s\n" "Guestbook" "30800" "✓ http://$$NODE_IP:$$GB_NP" || printf "%-12s %-8s %-12s\n" "Guestbook" "30800" "NOT SYNCED"; \
	OC_NP=$$(kubectl get svc -n opencost -l app.kubernetes.io/name=opencost -o jsonpath='{.items[0].spec.ports[?(@.nodePort)].nodePort}' 2>/dev/null || echo ""); \
	[ -n "$$OC_NP" ] && printf "%-12s %-8s %-12s\n" "OpenCost" "30903" "✓ http://$$NODE_IP:$$OC_NP" || printf "%-12s %-8s %-12s\n" "OpenCost" "30903" "NOT SYNCED"

test: ## Smoke test all platform endpoints (requires 'make ports' to be running)
	@echo ""
	@echo "=== FrugalZeus Platform Smoke Tests ==="
	@echo ""
	@PASS=1; \
	STATUS=$$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:3000/api/health 2>/dev/null); \
	if [ "$$STATUS" = "200" ]; then echo "  ✓ Grafana        http://localhost:3000  (HTTP $$STATUS)"; \
	else echo "  ✗ Grafana        NOT REACHABLE (HTTP $$STATUS) — run 'make ports'"; PASS=0; fi; \
	STATUS=$$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080 2>/dev/null); \
	if [ "$$STATUS" = "200" ] || [ "$$STATUS" = "307" ]; then echo "  ✓ Argo CD        http://localhost:8080  (HTTP $$STATUS)"; \
	else echo "  ✗ Argo CD        NOT REACHABLE (HTTP $$STATUS)"; PASS=0; fi; \
	STATUS=$$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8000 2>/dev/null); \
	if [ "$$STATUS" = "200" ]; then echo "  ✓ Guestbook      http://localhost:8000  (HTTP $$STATUS)"; \
	else echo "  ✗ Guestbook      NOT REACHABLE (HTTP $$STATUS) — still syncing?"; fi; \
	STATUS=$$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:9003 2>/dev/null); \
	if [ "$$STATUS" = "200" ] || [ "$$STATUS" = "301" ]; then echo "  ✓ OpenCost       http://localhost:9003  (HTTP $$STATUS)"; \
	else echo "  ✗ OpenCost       NOT REACHABLE (HTTP $$STATUS)"; fi; \
	echo ""; \
	if [ "$$PASS" = "1" ]; then echo "  All core services reachable. Run 'make observe' for full endpoint list."; \
	else echo "  Some services unreachable. Run 'make apply-apps && make sync-wait' then retry."; fi

clean: ## Tear down k3s completely (destructive)
	/usr/local/bin/k3s-uninstall.sh 2>/dev/null || echo "k3s uninstall script not found."
