#!/usr/bin/env bash
set -euo pipefail

# Find worker node names first (sorted naturally: worker, worker2, worker3, ...)
mapfile -t workers < <(
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        | awk '/worker/' \
        | sort -V
)

if ((${#workers[@]} < 5)); then
    echo "Expected at least 5 worker nodes, found ${#workers[@]}: ${workers[*]:-none}" >&2
    exit 1
fi

worker1="${workers[0]}"
worker2="${workers[1]}"
worker3="${workers[2]}"
worker4="${workers[3]}"
worker5="${workers[4]}"

echo "Using worker nodes: $worker1 $worker2 $worker3 $worker4 $worker5"

# 1) Label all selected workers as Kubernetes worker nodes
for node in "$worker1" "$worker2" "$worker3" "$worker4" "$worker5"; do
    kubectl label node "$node" node-role.kubernetes.io/worker='' --overwrite
done

# 2) Label first two workers as platform
kubectl label node "$worker1" mission-control.datastax.com/role=platform --overwrite
kubectl label node "$worker2" mission-control.datastax.com/role=platform --overwrite

# 3) Label next three workers as database
for node in "$worker3" "$worker4" "$worker5"; do
    kubectl label node "$node" mission-control.datastax.com/role=database --overwrite
done

# 4) Apply zone labels to database workers
kubectl label node "$worker3" topology.kubernetes.io/zone=zoneA --overwrite
kubectl label node "$worker4" topology.kubernetes.io/zone=zoneB --overwrite
kubectl label node "$worker5" topology.kubernetes.io/zone=zoneC --overwrite