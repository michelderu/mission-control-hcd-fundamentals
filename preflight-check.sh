#!/usr/bin/env bash
set -euo pipefail

failures=0

ok() {
  echo "[OK] $1"
}

warn() {
  echo "[WARN] $1"
}

err() {
  echo "[ERR] $1" >&2
  failures=$((failures + 1))
}

require_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "Found command: $cmd"
  else
    err "Missing required command: $cmd"
  fi
}

echo "Running Mission Control preflight checks..."

require_cmd kind
require_cmd kubectl
require_cmd helm
require_cmd docker
require_cmd htpasswd

if [[ -f "mc-overrides.yaml" ]]; then
  ok "Found file: mc-overrides.yaml"
else
  err "Missing required file: mc-overrides.yaml"
fi

if [[ -f ".env.example" ]]; then
  ok "Found file: .env.example"
else
  err "Missing required file: .env.example"
fi

if [[ -f "label-nodes.sh" ]]; then
  ok "Found file: label-nodes.sh"
else
  err "Missing required file: label-nodes.sh"
fi

if [[ -f "kind-cluster.yaml" ]]; then
  ok "Found file: kind-cluster.yaml"
else
  warn "kind-cluster.yaml not found (README references it for cluster creation)"
fi

if kubectl config get-contexts kind-mc >/dev/null 2>&1; then
  ok "Kubernetes context kind-mc exists"
else
  warn "Kubernetes context kind-mc not found yet (create cluster first)"
fi

current_context="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$current_context" == "kind-mc" ]]; then
  ok "Current kubectl context is kind-mc"
elif [[ -n "$current_context" ]]; then
  warn "Current kubectl context is $current_context (expected kind-mc)"
else
  warn "Current kubectl context is not set"
fi

cluster_mc_exists=0
while IFS= read -r cluster_name; do
  if [[ "$cluster_name" == "mc" ]]; then
    cluster_mc_exists=1
    break
  fi
done < <(kind get clusters 2>/dev/null || true)

if ((cluster_mc_exists == 1)); then
  ok "KinD cluster mc exists"
else
  warn "KinD cluster mc not found yet (run kind create cluster --name mc ...)"
fi

echo
if ((failures > 0)); then
  echo "Preflight failed with ${failures} error(s)." >&2
  exit 1
fi

echo "Preflight completed successfully."
