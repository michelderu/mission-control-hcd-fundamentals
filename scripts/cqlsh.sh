#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="hcd"
CLUSTER="hcd"
DATACENTER="dc1"
SUPERUSER_SECRET="hcd-superuser"
POD=""
CQL_QUERY=""

usage() {
  cat <<'USAGE'
Usage: scripts/cqlsh.sh [options]

Connect to Cassandra cqlsh in the HCD lab.

Options:
  -n, --namespace <ns>      Kubernetes namespace (default: hcd)
  -c, --cluster <name>      Cluster name prefix (default: hcd)
  -d, --dc <dc>             Datacenter (dc1|dc2|hcd-dc1|hcd-dc2), default: dc1
  -s, --secret <name>       Superuser secret name (default: hcd-superuser)
  -p, --pod <pod>           Cassandra pod name (skip auto-discovery)
  -e, --exec <cql>          Execute a CQL statement and exit
  -h, --help                Show this help

Examples:
  scripts/cqlsh.sh
  scripts/cqlsh.sh --dc dc2
  scripts/cqlsh.sh --exec "DESCRIBE KEYSPACES;"
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"; shift 2 ;;
    -c|--cluster)
      CLUSTER="$2"; shift 2 ;;
    -d|--dc)
      DATACENTER="$2"; shift 2 ;;
    -s|--secret)
      SUPERUSER_SECRET="$2"; shift 2 ;;
    -p|--pod)
      POD="$2"; shift 2 ;;
    -e|--exec)
      CQL_QUERY="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ "$DATACENTER" == hcd-* ]]; then
  CASS_DC="$DATACENTER"
else
  CASS_DC="hcd-$DATACENTER"
fi

SERVICE_HOST="${CLUSTER}-${CASS_DC}-service"

if [[ -z "$POD" ]]; then
  POD=$(kubectl get pods -n "$NAMESPACE" \
    -l "cassandra.datastax.com/cluster=${CLUSTER},cassandra.datastax.com/datacenter=${CASS_DC}" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}')
fi

if [[ -z "$POD" ]]; then
  echo "No running Cassandra pod found for datacenter ${CASS_DC} in namespace ${NAMESPACE}." >&2
  exit 1
fi

DB_USER=$(kubectl get secret "$SUPERUSER_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)
DB_PASS=$(kubectl get secret "$SUPERUSER_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

if [[ -n "$CQL_QUERY" ]]; then
  kubectl exec -it "$POD" -n "$NAMESPACE" -c cassandra -- \
    cqlsh -u "$DB_USER" -p "$DB_PASS" "$SERVICE_HOST" -e "$CQL_QUERY"
else
  kubectl exec -it "$POD" -n "$NAMESPACE" -c cassandra -- \
    cqlsh -u "$DB_USER" -p "$DB_PASS" "$SERVICE_HOST"
fi
