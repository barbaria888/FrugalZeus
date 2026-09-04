#!/usr/bin/env bash
# =============================================================================
# vault-init.sh — One-shot Vault initialisation for FrugalZeus
#
# Aurora-style: single key share, minimal shell, no Python.
# Run once after 'make bootstrap'. Safe to skip if Vault is already initialised.
# =============================================================================
set -euo pipefail

VAULT_NS="vault"
VAULT_POD="vault-0"
INIT_FILE="/tmp/vault-init.json"      # gitignored — keep this file safe

echo ""
echo "=== FrugalZeus: Vault Init ==="

# ── 1. Wait for the pod ────────────────────────────────────────────────────
echo "Waiting for vault-0 to be Ready..."
kubectl wait --for=condition=Ready pod/"$VAULT_POD" \
  -n "$VAULT_NS" --timeout=180s

# ── 2. Skip if already initialised ────────────────────────────────────────
INIT_STATUS=$(kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  vault status -format=json 2>/dev/null | grep -o '"initialized":[^,}]*' || true)

if echo "$INIT_STATUS" | grep -q "true"; then
  echo "Vault is already initialised. Loading token from $INIT_FILE"
  ROOT=$(jq -r .root_token "$INIT_FILE")
else
  # ── 3. Initialise (1 key share is fine for a portfolio demo)
  #       For production use -key-shares=5 -key-threshold=3 (Shamir's Secret Sharing)
  echo "Initialising Vault (1-of-1 key share — demo mode)..."
  INIT=$(kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
    vault operator init -key-shares=1 -key-threshold=1 -format=json)

  echo "$INIT" > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  echo "  ✓ Init output saved to $INIT_FILE (never commit this file)"

  # ── 4. Unseal
  UNSEAL=$(echo "$INIT" | jq -r '.unseal_keys_b64[0]')
  kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- vault operator unseal "$UNSEAL"
  echo "  ✓ Vault unsealed"

  ROOT=$(echo "$INIT" | jq -r '.root_token')
fi

# ── 5. Enable secrets engine (idempotent) ─────────────────────────────────
echo "Enabling KV-v2 secrets engine at path 'secret'..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault secrets enable -path=secret kv-v2 2>/dev/null || \
  echo "  (already enabled — skipping)"

# ── 6. Enable Kubernetes auth (idempotent) ────────────────────────────────
echo "Enabling Kubernetes auth method..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault auth enable kubernetes 2>/dev/null || \
  echo "  (already enabled — skipping)"

kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"
echo "  ✓ Kubernetes auth configured"

# ── 7. Policy: ESO can read any secret path ───────────────────────────────
echo "Writing ESO policy..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault policy write eso - <<'EOF'
path "secret/data/*" { capabilities = ["read"] }
EOF
echo "  ✓ Policy 'eso' written"

# ── 8. Role: bind ESO's ServiceAccount to the policy ──────────────────────
echo "Creating Kubernetes auth role 'external-secrets'..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso \
    ttl=1h
echo "  ✓ Role 'external-secrets' created"

# ── 9. Seed demo secrets (so the first ExternalSecret works out of the box)
echo "Seeding demo secrets for team-alpha..."
kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT" vault kv put secret/tenants/team-alpha/app \
    DB_PASSWORD="demo-db-pass" \
    API_KEY="demo-api-key"
echo "  ✓ Demo secrets seeded at secret/tenants/team-alpha/app"

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo "✓ Vault ready."
echo ""
echo "  Vault UI:     http://<NODE-IP>:8200  (or: kubectl port-forward svc/vault -n vault 8200:8200)"
echo "  Root token:   $INIT_FILE             (keep safe, gitignored)"
echo ""
echo "  To add/update a secret:  make vault-seed KEY=MY_KEY VALUE=my-val"
echo "  To check ESO sync:       kubectl get externalsecret -A"
echo ""
