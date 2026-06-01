#!/usr/bin/env bash
# Preflight: foundation (CLI tools) and runtime resources only — no repo file checks.
# Run from the repository root:  ./scripts/preflight-check.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

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
    ok "Command available: $cmd"
  else
    err "Missing command: $cmd"
  fi
}

echo "Running Mission Control preflight (foundation + resources)..."

echo
echo "Foundation — required CLI tools"
require_cmd kind
require_cmd kubectl
require_cmd helm
require_cmd docker
require_cmd htpasswd

echo
echo "Resources — runtime"
if docker info >/dev/null 2>&1; then
  ok "Docker daemon is reachable"
else
  err "Docker daemon is not reachable (start Docker or check permissions)"
fi

if kind version >/dev/null 2>&1; then
  ok "kind CLI responds ($(kind version 2>/dev/null | head -1))"
else
  err "kind CLI failed"
fi

if helm version >/dev/null 2>&1; then
  ok "helm CLI responds ($(helm version --short 2>/dev/null | head -1))"
else
  err "helm CLI failed"
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
  if kubectl config get-contexts kind-mc >/dev/null 2>&1; then
    ok "Kubernetes context kind-mc exists"
  else
    warn "KinD cluster mc exists but context kind-mc is missing"
  fi
  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ "$current_context" == "kind-mc" ]]; then
    ok "Current kubectl context is kind-mc"
  elif [[ -n "$current_context" ]]; then
    warn "Current kubectl context is $current_context (expected kind-mc after cluster create)"
  else
    warn "Current kubectl context is not set"
  fi
  if kubectl get nodes --context kind-mc >/dev/null 2>&1; then
    ready_nodes="$(kubectl get nodes --context kind-mc --no-headers 2>/dev/null | awk '$2=="Ready" {c++} END {print c+0}')"
    total_nodes="$(kubectl get nodes --context kind-mc --no-headers 2>/dev/null | wc -l)"
    if [[ "$ready_nodes" -eq "$total_nodes" ]] && ((total_nodes > 0)); then
      ok "All $total_nodes node(s) Ready (context kind-mc)"
    else
      warn "Nodes not all Ready: $ready_nodes/$total_nodes (context kind-mc)"
    fi
  else
    warn "Cannot reach API server for context kind-mc"
  fi
else
  warn "KinD cluster mc not found yet (create with kind create cluster --name mc ...)"
fi

echo
if ((failures > 0)); then
  echo "Preflight failed with ${failures} error(s)." >&2
  exit 1
fi

echo "Preflight completed successfully."
