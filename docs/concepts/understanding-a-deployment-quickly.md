# How to Quickly Understand a Specific Deployment

Use this checklist when you inherit or debug a Mission Control + HCD deployment and need fast situational awareness.

## 1) Identify what was intended

Start with desired state inputs:

1. Helm values:
   - `manifests/mission-control/overrides.yaml` (environment-specific overrides)
   - `manifests/mission-control/values.yaml` (base values, if pinned)
2. Runtime custom resources:
   - `MissionControlCluster` CR(s)
   - HCD/Cassandra CRs (for actual data-plane topology)

What to look for:

- Which components are enabled/disabled (`ui`, `dex`, `loki`, `mimir`, `aggregator`, `agent`, ingress).
- Storage mode (embedded MinIO vs external S3).
- Security/TLS expectations (mounted cert secrets, HTTPS probes, issuer/CA choices).
- Scale and placement hints (replicas, node selectors, tolerations, zone settings).

Commands:

```bash
# Helm release values actually applied
helm list -A
helm get values -n mission-control mission-control -a

# If you keep files in repo
rg "enabled:|minio|loki|mimir|dex|aggregator|agent|ingress" manifests/mission-control/values.yaml manifests/mission-control/overrides.yaml

# MissionControl CRs and HCD/Cassandra CRs
kubectl get missioncontrolclusters -A
kubectl get cassandradatacenters -A
kubectl get cassandraclusters -A
```

## 2) Verify what is actually running

Check live Kubernetes state against intended config:

- Workloads: Deployments, StatefulSets, Pods
- Network: Services, Ingress/Gateway
- Config: ConfigMaps, Secrets
- Storage: PVCs/PVs

What to look for:

- CrashLoopBackOff / ImagePullBackOff / Pending pods.
- Replica mismatch (desired vs available).
- Missing PVC bindings for stateful services.
- Services pointing to zero ready endpoints.

Commands:

```bash
kubectl get deploy,statefulset,pod -n mission-control -o wide
kubectl get svc,ingress -n mission-control
kubectl get cm,secret -n mission-control
kubectl get pvc,pv -n mission-control

# Quick failure view
kubectl get pods -A | rg "CrashLoopBackOff|ImagePullBackOff|Pending|Error"
kubectl describe pod -n mission-control <pod-name>
kubectl logs -n mission-control <pod-name> --all-containers --tail=200
```

## 3) Trace the observability path first

For fast confidence, verify telemetry pipeline in order:

1. Vector ingestion (agent/aggregator depending on mode)
2. Loki ingestion/query path (logs)
3. Mimir remote-write/query path (metrics)
4. Alertmanager route/receiver config

What to look for:

- Vector sinks correctly target Loki/Mimir endpoints.
- TLS cert secrets mounted where expected.
- Object storage connectivity for Loki/Mimir.
- Alertmanager config loaded and not stuck on parse errors.

Commands:

```bash
# Core observability workloads
kubectl get pod -n mission-control | rg "vector|loki|mimir|alertmanager"

# Check Vector config and sinks
kubectl get cm -n mission-control | rg "vector|aggregator"
kubectl get cm -n mission-control <vector-configmap> -o yaml

# Check logs for pipeline errors
kubectl logs -n mission-control deploy/mission-control-aggregator --tail=200
kubectl logs -n mission-control statefulset/mission-control-loki-write --tail=200
kubectl logs -n mission-control deploy/mission-control-mimir-distributor --tail=200

# TLS and object-storage related secrets
kubectl get secret -n mission-control | rg "loki|mimir|minio|tls"
```

## 4) Confirm control-plane health

Check Mission Control platform services:

- Mission Control operator is healthy and reconciling.
- UI and API services are reachable.
- Dex/auth flow aligns with configured base URL and redirect settings.

What to look for:

- Operator events showing reconciliation failures.
- API/UI pods healthy but service/ingress miswired.
- Auth redirect loops caused by incorrect canonical URL config.

Commands:

```bash
kubectl get deploy,pod,svc -n mission-control | rg "operator|ui|api|dex"
kubectl logs -n mission-control deploy/mission-control --tail=200
kubectl logs -n mission-control deploy/mission-control-ui --tail=200
kubectl logs -n mission-control deploy/mission-control-dex --tail=200

# Reconciliation and warning events
kubectl get events -n mission-control --sort-by=.metadata.creationTimestamp | tail -n 100
```

## 5) Confirm data-plane intent vs reality (HCD/Cassandra)

If the deployment includes database clusters:

- Verify HCD/Cassandra custom resources and status conditions.
- Verify StatefulSet replicas, anti-affinity, and zone placement.
- Verify PVC size/class/binding and pod-to-volume attachment.

What to look for:

- Topology mismatch (expected racks/zones not realized).
- Under-replicated nodes due to scheduling constraints.
- Disk or storage class issues blocking startup.

Commands:

```bash
# HCD/Cassandra custom resources and status
kubectl get cassandraclusters,cassandradatacenters -A -o wide
kubectl describe cassandradatacenter -n <ns> <dc-name>

# Stateful runtime and storage checks
kubectl get statefulset,pod -n <ns> -o wide
kubectl get pvc -n <ns>
kubectl describe pvc -n <ns> <pvc-name>

# Placement checks
kubectl get pod -n <ns> -o wide | rg "<dc-or-cluster-name>"
kubectl get nodes --show-labels
```

## 6) Build a 5-line deployment summary

When done, summarize in this format:

1. **Enabled components:** (UI, Dex, Vector mode, Loki, Mimir, Alertmanager, HCD/Cassandra)
2. **Storage model:** (embedded MinIO vs external S3, PVC usage)
3. **Security model:** (TLS/auth key points)
4. **Current health:** (green/yellow/red with top blockers)
5. **Next actions:** (highest-impact fixes first)

Helpful one-shot summary commands:

```bash
kubectl get deploy,statefulset,pod,svc,pvc -n mission-control
kubectl get missioncontrolclusters,cassandraclusters,cassandradatacenters -A
helm get values -n mission-control mission-control -a
```

## Red flags worth checking immediately

- Values say component enabled, but no matching workload exists.
- Pod is healthy but service has no endpoints.
- StatefulSet exists but PVCs are Pending.
- TLS enabled but referenced secret missing/misnamed.
- Loki/Mimir enabled but object storage creds/endpoint mismatch.
- Operator running but CR status not progressing.

## Fast mental model

- **Values + CRs** define intent.
- **Operator/controllers** translate intent into resources.
- **Pods/Services/PVCs** reveal execution reality.
- Most incidents are mismatches between those three layers.
