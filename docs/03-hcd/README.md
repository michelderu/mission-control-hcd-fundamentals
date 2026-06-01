# Installing, updating, and upgrading HCD

Deploy **Hyper-Converged Database (HCD)** with a `MissionControlCluster` custom resource.

**Prerequisites**

- 📂 Run from the **repository root**.
- [Kubernetes (step 1)](../01-kubernetes/README.md) and [Mission Control (step 2)](../02-mission-control/README.md) are running.
- Same **`PROFILE`** as KinD ([topology profiles](../01-kubernetes/README.md#topology-profiles): `minimal`, `3-racks`, or `2-dcs`).

➡️ **Next:** [CQL (step 4)](../04-cql/README.md) · 💡 optional: [Data API](../05-data-api/README.md) · [Monitoring](../06-monitoring/README.md)

## Pick your manifest

All profiles use namespace **`hcd`**. The manifest file name matches **`PROFILE`**:

| `PROFILE` | Manifest | Datacenters | Cassandra pods |
|-----------|----------|-------------|----------------|
| `minimal` | `charts/hcd/mission-control-cluster-minimal.yaml` | `hcd-dc1` | 1 |
| `3-racks` | `charts/hcd/mission-control-cluster-3-racks.yaml` | `hcd-dc1` | 3 |
| `2-dcs` | `charts/hcd/mission-control-cluster-2-dcs.yaml` | `hcd-dc1`, `hcd-dc2` | 6 |

Lab YAMLs use `serverVersion: "1.2.5"`, internode encryption, and **`racks[].nodeAffinityLabels`** aligned with `./scripts/apply-topology-labels.sh "${PROFILE}"`.

> 📦 **Resources (every profile):** `heapSize: 512Mi`, pod `memory` request `1280Mi` / limit `1536Mi`, PVC `2Gi` per node.

## Install

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](../02-mission-control/README.md#access-the-ui)).
2. Ensure project **`hcd`** exists (namespace labeled — see ⌨️ CLI below if needed).
3. **Create Cluster** (simple or expert mode) and match your KinD **`PROFILE`**, or skip if you use the CLI manifest.

### ⌨️ CLI

Checked-in manifests (recommended for reproducibility):

```bash
export PROFILE=minimal   # same value as KinD step 1

kubectl create namespace hcd

kubectl label namespace hcd mission-control.datastax.com/is-project=true
kubectl annotate namespace hcd mission-control.datastax.com/project-name=hcd

kubectl apply -f charts/hcd/mission-control-cluster-${PROFILE}.yaml
```

## Watch rollout

```bash
watch kubectl get pods -n hcd -o wide --sort-by=.spec.nodeName
```

| `PROFILE` | What to expect |
|-----------|----------------|
| `minimal` | One Cassandra pod on the database worker |
| `3-racks` | Three pods (`hcd-dc1-rack1-sts-0`, `rack2`, `rack3`) |
| `2-dcs` | DC1 racks ready first, then DC2 (`hcd-dc2-rack*-sts-0`) |

## Reconciliation and troubleshooting

```bash
kubectl get missioncontrolcluster -n hcd
kubectl describe missioncontrolcluster hcd -n hcd
kubectl get k8ssandracluster,cassandradatacenter -n hcd
kubectl get pods -n hcd -o wide --sort-by=.spec.nodeName
kubectl logs -n mission-control deploy/mission-control-operator --tail=50
```

## Update / upgrade HCD

Edit the manifest, then re-apply with the same **`PROFILE`**:

```bash
kubectl apply -f charts/hcd/mission-control-cluster-${PROFILE}.yaml
```

For large topology changes, deleting and recreating the `MissionControlCluster` may be simpler.

## Remove an HCD cluster

```bash
kubectl delete missioncontrolcluster hcd -n hcd
kubectl delete namespace hcd
```

Or delete the whole KinD cluster ([Kubernetes guide](../01-kubernetes/README.md)).
