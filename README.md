# Mission Control + HCD fundamentals (KinD lab)

Local lab for **Mission Control** on **KinD** with **embedded MinIO** and **HCD** clusters pinned to platform/database topology labels.

## Runbook (in order)

| Step | Guide | What you do |
|------|--------|-------------|
| **1** | [**Setting up Kubernetes**](docs/01-kubernetes/README.md) | KinD cluster `mc`, topology labels, verify nodes |
| **2** | [**Mission Control — install / upgrade**](docs/02-mission-control/README.md) | cert-manager, Helm install, UI, upgrades |
| **3** | [**HCD — install / upgrade**](docs/03-hcd/README.md) | `kubectl apply` `mission-control-cluster-${PROFILE}.yaml` |
| **4** | [**CQL (cqlsh)**](docs/04-cql/README.md) | Optional `CqlConnectivity` gateway; MC CQL console or CLI |
| **5** | [**Data API**](docs/05-data-api/README.md) | Optional — HTTP gateway for `hcd-dc1` (any profile) |
| **6** | [**Monitoring**](docs/06-monitoring/README.md) | MC UI Observability; optional Grafana (any profile) |

## Repo layout

| Path | Purpose |
|------|---------|
| [`docs/01-kubernetes/`](docs/01-kubernetes/README.md) | KinD profiles, labels, cluster lifecycle |
| [`docs/02-mission-control/`](docs/02-mission-control/README.md) | Helm values, install, upgrade, UI |
| [`docs/03-hcd/`](docs/03-hcd/README.md) | HCD CRs, UI projects, rollout |
| [`docs/04-cql/`](docs/04-cql/README.md) | CQL console and `cqlsh` access |
| [`docs/05-data-api/`](docs/05-data-api/README.md) | Data API gateways |
| [`docs/06-monitoring/`](docs/06-monitoring/README.md) | MC UI metrics, Grafana overlay |
| [`kind/`](kind/README.md) | KinD YAML configs (pointer to docs) |
| [`charts/mission-control/`](charts/mission-control/) | Pinned `values.yaml`, `overrides.yaml`, optional `enable-grafana.yaml` |
| [`charts/hcd/`](charts/hcd/) | `MissionControlCluster` + optional `data-api/` gateways |
| [`scripts/`](scripts/) | `preflight-check.sh`, `apply-topology-labels.sh` |
| [`docs/concepts/`](docs/concepts/README.md) | Architecture and wiring reference |

## Lab conventions

**Repository root:** run every command from the root of this git clone (`charts/`, `kind/`, `scripts/` are relative to it). Runbooks list **Mission Control UI** steps before **CLI** when both are available.

**Choose one topology profile** and use the same name in steps 1–3. Set it once in your shell:

```bash
export PROFILE=minimal   # minimal | 3-racks | 2-dcs
```

| Item | Value |
|------|--------|
| HCD namespace | **`hcd`** (all profiles) |
| Mission Control namespace | **`mission-control`** |
| `MissionControlCluster` | **`hcd`** |
| Superuser Secret | **`hcd-superuser`** (namespace `hcd`) |

| Profile | KinD config | HCD manifest | Datacenters | Cassandra pods |
|---------|-------------|--------------|-------------|----------------|
| **minimal** (default) | `kind/kind-cluster-minimal.yaml` | `charts/hcd/mission-control-cluster-minimal.yaml` | `hcd-dc1` | 1 |
| **3-racks** | `kind/kind-cluster-3-racks.yaml` | `charts/hcd/mission-control-cluster-3-racks.yaml` | `hcd-dc1` | 3 |
| **2-dcs** | `kind/kind-cluster-2-dcs.yaml` | `charts/hcd/mission-control-cluster-2-dcs.yaml` | `hcd-dc1`, `hcd-dc2` | 6 |

Steps 4–6 work for every profile. Optional: `charts/hcd/cql/cql-connectivity-dc1.yaml` (CQL gateway) · `charts/hcd/data-api/data-api-dc1.yaml` (Data API) — both target **`hcd-dc1`**.

To switch profiles, delete the KinD cluster or the **`hcd`** namespace before re-running with a different `PROFILE`.

## Assumptions

- Docker, KinD, `kubectl`, Helm installed.

## Concepts (reference)

- [`docs/concepts/README.md`](docs/concepts/README.md) — index
- [`docs/concepts/deployment-structure.md`](docs/concepts/deployment-structure.md) — Helm + operator flow
- [`docs/concepts/software-components-wiring.md`](docs/concepts/software-components-wiring.md) — component map
- [`docs/concepts/understanding-a-deployment-quickly.md`](docs/concepts/understanding-a-deployment-quickly.md) — triage checklist

## What Mission Control is

Mission Control is the management plane for DataStax Cassandra/HCD on Kubernetes: UI, APIs, and operators that reconcile `MissionControlCluster` resources into running database topologies.
