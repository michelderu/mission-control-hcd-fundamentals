# KinD cluster configs

KinD YAML for this lab. **Full steps:** [`docs/01-kubernetes/README.md`](../docs/01-kubernetes/README.md).

**Repository root:** run commands from the clone root.

```bash
export PROFILE=minimal   # minimal | 3-racks | 2-dcs

kind create cluster --name mc --config kind/kind-cluster-${PROFILE}.yaml
./scripts/apply-topology-labels.sh "${PROFILE}"
```

| `PROFILE` | File |
|-----------|------|
| `minimal` (default) | [`kind-cluster-minimal.yaml`](kind-cluster-minimal.yaml) |
| `3-racks` | [`kind-cluster-3-racks.yaml`](kind-cluster-3-racks.yaml) |
| `2-dcs` | [`kind-cluster-2-dcs.yaml`](kind-cluster-2-dcs.yaml) |

`role` labels are in each YAML (`kubeadmConfigPatches`). `topology.kubernetes.io/region` / `zone` are applied by the script.
