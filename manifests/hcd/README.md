# HCD MissionControlCluster manifests

**Prerequisites**

- 📂 Paths in the runbooks are relative to the **repository root**.
- Namespace **`hcd`** for all profiles.

```bash
export PROFILE=minimal   # minimal | 3-racks | 2-dcs — match KinD

kubectl apply -f manifests/hcd/mission-control-cluster-${PROFILE}.yaml
```

| `PROFILE` | File | Layout |
|-----------|------|--------|
| `minimal` | `mission-control-cluster-minimal.yaml` | 1 DC, 1 rack |
| `3-racks` | `mission-control-cluster-3-racks.yaml` | 1 DC, 3 racks |
| `2-dcs` | `mission-control-cluster-2-dcs.yaml` | 2 DCs × 3 racks |

| Chart | Guide |
|-------|--------|
| 💡 `cql/cql-connectivity-dc1.yaml` | [CQL (step 4)](../../docs/04-cql.md) |
| 💡 `data-api/data-api-dc1.yaml` | [Data API (step 5)](../../docs/05-data-api.md) |

➡️ **Install:** [`docs/03-hcd.md`](../../docs/03-hcd.md)
