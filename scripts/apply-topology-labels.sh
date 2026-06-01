#!/usr/bin/env bash
# Apply topology.kubernetes.io/region (datacenter) and zone (rack) after KinD create.
# Kubelet cannot set these reserved labels; kubectl with admin credentials can.
#
# Run from the repository root:
#   ./scripts/apply-topology-labels.sh [minimal|3-racks|2-dcs]
# Default profile: minimal
set -euo pipefail

PROFILE="${1:-minimal}"

mapfile -t workers < <(
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | awk '/worker/' \
    | sort -V
)

label_topology() {
  local node="$1"
  local region="$2"
  local zone="$3"
  kubectl label node "$node" \
    topology.kubernetes.io/region="$region" \
    topology.kubernetes.io/zone="$zone" \
    --overwrite
}

echo "Topology profile: ${PROFILE}"
echo "Workers: ${workers[*]:-none}"

case "$PROFILE" in
minimal)
  if ((${#workers[@]} < 2)); then
    echo "Profile minimal expects 2 workers, found ${#workers[@]}" >&2
    exit 1
  fi
  label_topology "${workers[1]}" dc1 rack1
  ;;
3-racks)
  if ((${#workers[@]} < 5)); then
    echo "Profile 3-racks expects 5 workers, found ${#workers[@]}" >&2
    exit 1
  fi
  label_topology "${workers[2]}" dc1 rack1
  label_topology "${workers[3]}" dc1 rack2
  label_topology "${workers[4]}" dc1 rack3
  ;;
2-dcs)
  if ((${#workers[@]} < 8)); then
    echo "Profile 2-dcs expects 8 workers, found ${#workers[@]}" >&2
    exit 1
  fi
  label_topology "${workers[2]}" dc1 rack1
  label_topology "${workers[3]}" dc1 rack2
  label_topology "${workers[4]}" dc1 rack3
  label_topology "${workers[5]}" dc2 rack1
  label_topology "${workers[6]}" dc2 rack2
  label_topology "${workers[7]}" dc2 rack3
  ;;
*)
  echo "Unknown profile: ${PROFILE}" >&2
  echo "Usage: $0 [minimal|3-racks|2-dcs]" >&2
  exit 1
  ;;
esac

echo "Done! Listing the nodes with the new labels..."
kubectl get nodes -L mission-control.datastax.com/role,topology.kubernetes.io/region,topology.kubernetes.io/zone
