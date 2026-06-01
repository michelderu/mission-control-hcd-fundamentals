# HCD MissionControlCluster manifests

**Repository root:** paths in the runbooks are relative to the clone root. Namespace **`hcd`** for all profiles.

```bash
export PROFILE=minimal   # minimal | 3-racks | 2-dcs — match KinD

kubectl apply -f charts/hcd/mission-control-cluster-${PROFILE}.yaml
```

| `PROFILE` | File | Layout |
|-----------|------|--------|
| `minimal` | `mission-control-cluster-minimal.yaml` | 1 DC, 1 rack |
| `3-racks` | `mission-control-cluster-3-racks.yaml` | 1 DC, 3 racks |
| `2-dcs` | `mission-control-cluster-2-dcs.yaml` | 2 DCs × 3 racks |

**CQL gateway (optional):** [`cql/cql-connectivity-dc1.yaml`](cql/cql-connectivity-dc1.yaml) · **Data API (optional):** [`data-api/data-api-dc1.yaml`](data-api/data-api-dc1.yaml)

**Install:** [`docs/03-hcd/README.md`](../../docs/03-hcd/README.md) · **CQL:** [`docs/04-cql/README.md`](../../docs/04-cql/README.md)
