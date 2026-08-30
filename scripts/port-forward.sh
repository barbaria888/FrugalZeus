#!/bin/bash
set -euo pipefail

# ==============================================================================
# FrugalZeus Platform Port Forwarder
# ==============================================================================

PIDS=()
LOG_FILES=()

cleanup() {
    # Disable trap during cleanup to avoid recursion
    trap - EXIT INT TERM HUP
    echo ""
    echo "Stopping all active port forwards..."
    for pid in "${PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait for child processes to terminate
    wait 2>/dev/null || true

    # Clean up temporary logs
    for log in "${LOG_FILES[@]:-}"; do
        rm -f "$log" 2>/dev/null || true
    done

    echo "All port forwards stopped cleanly."
}

trap cleanup EXIT INT TERM HUP

# 1. Verify Prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: 'kubectl' command not found in PATH." >&2
    exit 1
fi

if ! kubectl version --client >/dev/null 2>&1; then
    echo "ERROR: Unable to execute kubectl." >&2
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Please check your kubeconfig." >&2
    exit 1
fi

# 2. Service Definitions: [DisplayName]|[Namespace]|[PreferredServiceName]|[LabelSelector]|[LocalPort]|[PreferredTargetPort]
SERVICES=(
    "Grafana|monitoring|prometheus-grafana|app.kubernetes.io/name=grafana|3000|80"
    "Argo CD|argocd|argocd-server|app.kubernetes.io/name=argocd-server|8080|80"
    "Guestbook Demo|tenant-guestbook|guestbook-ui|app=guestbook-ui|8000|80"
    "OpenCost|opencost|opencost|app.kubernetes.io/name=opencost|9003|9003"
)

RESOLVED_SERVICES=()
MISSING_ERRORS=()

# 3. Discover and Validate Services
for entry in "${SERVICES[@]}"; do
    IFS='|' read -r DISPLAY_NAME NAMESPACE PREFERRED_NAME LABEL_SELECTOR LOCAL_PORT TARGET_PORT <<< "$entry"

    # Check Namespace
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        MISSING_ERRORS+=("• $DISPLAY_NAME: Namespace '$NAMESPACE' does not exist.")
        continue
    fi

    # Check Service by preferred name first, then fallback to label selector
    ACTUAL_SVC=""
    if kubectl get svc "$PREFERRED_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        ACTUAL_SVC="$PREFERRED_NAME"
    else
        # Try label selector
        ACTUAL_SVC=$(kubectl get svc -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi

    if [ -z "$ACTUAL_SVC" ]; then
        MISSING_ERRORS+=("• $DISPLAY_NAME: Service '$PREFERRED_NAME' (selector: $LABEL_SELECTOR) not found in namespace '$NAMESPACE'.")
        continue
    fi

    # Verify Target Port exists on Service (or fallback to first available port)
    RESOLVED_PORT="$TARGET_PORT"
    PORT_CHECK=$(kubectl get svc "$ACTUAL_SVC" -n "$NAMESPACE" -o jsonpath="{.spec.ports[?(@.port==$TARGET_PORT)].port}" 2>/dev/null || true)
    if [ -z "$PORT_CHECK" ]; then
        # Check if 443 is available for Argo CD if port 80 wasn't found
        if [ "$NAMESPACE" = "argocd" ]; then
            HTTPS_PORT=$(kubectl get svc "$ACTUAL_SVC" -n "$NAMESPACE" -o jsonpath="{.spec.ports[?(@.port==443)].port}" 2>/dev/null || true)
            if [ -n "$HTTPS_PORT" ]; then
                RESOLVED_PORT="443"
            fi
        else
            FIRST_PORT=$(kubectl get svc "$ACTUAL_SVC" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
            if [ -n "$FIRST_PORT" ]; then
                RESOLVED_PORT="$FIRST_PORT"
            else
                MISSING_ERRORS+=("• $DISPLAY_NAME: Service '$ACTUAL_SVC' in namespace '$NAMESPACE' has no exposed ports.")
                continue
            fi
        fi
    fi

    RESOLVED_SERVICES+=("$DISPLAY_NAME|$NAMESPACE|$ACTUAL_SVC|$LOCAL_PORT|$RESOLVED_PORT")
done

# 4. Fail loudly if any required service is missing
if [ ${#MISSING_ERRORS[@]} -gt 0 ]; then
    echo "" >&2
    echo "================================================================================" >&2
    echo " FrugalZeus Platform Error: Required services are not ready or missing" >&2
    echo "================================================================================" >&2
    for err in "${MISSING_ERRORS[@]}"; do
        echo "  $err" >&2
    done
    echo "" >&2
    echo "Diagnosis:" >&2
    echo "  The Argo CD GitOps applications may still be syncing or provisioning." >&2
    echo "  Run 'make status' or 'kubectl get applications -n argocd' to inspect health." >&2
    echo "================================================================================" >&2
    exit 1
fi

# 5. Start Port Forwards with Verification
STARTED_DISPLAY=()

for entry in "${RESOLVED_SERVICES[@]}"; do
    IFS='|' read -r DISPLAY_NAME NAMESPACE SVC LOCAL_PORT TARGET_PORT <<< "$entry"

    LOG_FILE=$(mktemp "/tmp/frugalzeus-pf-${NAMESPACE}-${SVC}-XXXXXX.log" 2>/dev/null || echo "scratch/pf-${NAMESPACE}-${SVC}.log")
    LOG_FILES+=("$LOG_FILE")

    # Launch kubectl port-forward in background
    kubectl port-forward "svc/$SVC" -n "$NAMESPACE" "${LOCAL_PORT}:${TARGET_PORT}" > "$LOG_FILE" 2>&1 &
    PF_PID=$!
    PIDS+=("$PF_PID")

    # Brief delay to detect immediate crash (e.g. port already in use)
    sleep 0.8

    if ! kill -0 "$PF_PID" 2>/dev/null; then
        echo "" >&2
        echo "ERROR: Failed to establish port-forward for $DISPLAY_NAME ($NAMESPACE/$SVC on local port $LOCAL_PORT)." >&2
        if [ -s "$LOG_FILE" ]; then
            echo "--- kubectl error log ---" >&2
            cat "$LOG_FILE" >&2
            echo "-------------------------" >&2
        fi
        exit 1
    fi

    STARTED_DISPLAY+=("  • $(printf '%-18s' "$DISPLAY_NAME") http://localhost:${LOCAL_PORT}  ->  ${NAMESPACE}/${SVC}:${TARGET_PORT}")
done

# 6. Retrieve Credentials
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<admin secret removed or customized>")

# 7. Print Dashboard
echo ""
echo "================================================================================"
echo "                   FrugalZeus Platform Access Active                            "
echo "================================================================================"
echo ""
echo "Active Local Port Forwards:"
for line in "${STARTED_DISPLAY[@]}"; do
    echo "$line"
done
echo ""
echo "Platform Credentials:"
echo "  • Argo CD:    admin / ${ARGO_PASS}"
echo "  • Grafana:    admin / platform-admin"
echo ""
echo "Press Ctrl+C to stop all port forwards."
echo "================================================================================"

# Wait indefinitely on all background processes
wait
