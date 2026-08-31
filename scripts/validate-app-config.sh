#!/usr/bin/env bash
set -eo pipefail

CONFIG_FILE="${1:-}"

if [ -z "$CONFIG_FILE" ]; then
  echo "Error: No config file specified."
  echo "Usage: $0 <path-to-config.yaml>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found at '$CONFIG_FILE'."
  exit 1
fi

echo "Validating application config: $CONFIG_FILE"

# If yq is available, validate using yq
if command -v yq &> /dev/null; then
  # 1. Validate .name
  APP_NAME=$(yq '.name // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "null" ]; then
    echo "  [ERROR] Validation failed: '.name' is missing or empty."
    exit 1
  fi
  echo "  [OK] App name: $APP_NAME"

  # 2. Validate .source.repoURL
  REPO_URL=$(yq '.source.repoURL // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -z "$REPO_URL" ] || [ "$REPO_URL" = "null" ]; then
    echo "  [ERROR] Validation failed: '.source.repoURL' is missing or empty."
    exit 1
  fi
  echo "  [OK] Source repo: $REPO_URL"

  # 3. Validate .source.path
  SOURCE_PATH=$(yq '.source.path // empty' "$CONFIG_FILE" 2>/dev/null || true)
  if [ -z "$SOURCE_PATH" ] || [ "$SOURCE_PATH" = "null" ]; then
    echo "  [ERROR] Validation failed: '.source.path' is missing or empty."
    exit 1
  fi
  echo "  [OK] Source path: $SOURCE_PATH"

  # 4. Validate at least one environment has enabled: true
  ENABLED_COUNT=$(yq '[.environments[]? | select(.enabled == true)] | length' "$CONFIG_FILE" 2>/dev/null || echo "0")
  if [ -z "$ENABLED_COUNT" ] || [ "$ENABLED_COUNT" = "0" ] || [ "$ENABLED_COUNT" = "null" ]; then
    echo "  [ERROR] Validation failed: At least one environment under '.environments' must have 'enabled: true'."
    exit 1
  fi
  echo "  [OK] Enabled environments found: $ENABLED_COUNT"

elif command -v python3 &> /dev/null || command -v python &> /dev/null; then
  PY_CMD=$(command -v python3 || command -v python)
  $PY_CMD - <<EOF
import sys, yaml

with open("$CONFIG_FILE", "r", encoding="utf-8") as f:
    try:
        data = yaml.safe_load(f)
    except Exception as e:
        print(f"  [ERROR] Validation failed: Invalid YAML syntax ({e})")
        sys.exit(1)

if not data or not isinstance(data, dict):
    print("  [ERROR] Validation failed: Config file is empty or not a valid dictionary.")
    sys.exit(1)

name = data.get("name")
if not name:
    print("  [ERROR] Validation failed: '.name' is missing or empty.")
    sys.exit(1)
print(f"  [OK] App name: {name}")

source = data.get("source") or {}
repo_url = source.get("repoURL")
if not repo_url:
    print("  [ERROR] Validation failed: '.source.repoURL' is missing or empty.")
    sys.exit(1)
print(f"  [OK] Source repo: {repo_url}")

source_path = source.get("path")
if not source_path:
    print("  [ERROR] Validation failed: '.source.path' is missing or empty.")
    sys.exit(1)
print(f"  [OK] Source path: {source_path}")

envs = data.get("environments") or {}
enabled_envs = [env for env, cfg in envs.items() if isinstance(cfg, dict) and cfg.get("enabled") is True]
if not enabled_envs:
    print("  [ERROR] Validation failed: At least one environment under '.environments' must have 'enabled: true'.")
    sys.exit(1)
print(f"  [OK] Enabled environments found: {len(enabled_envs)} ({', '.join(enabled_envs)})")
EOF
else
  echo "Error: Neither 'yq' nor 'python' (with pyyaml) found to validate config."
  exit 1
fi

echo "[OK] Validation passed for $CONFIG_FILE"
exit 0
