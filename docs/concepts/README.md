# Concepts

Architecture and wiring reference for this lab — not install steps.

**Prerequisites**

- 📂 Step-by-step runbooks live under [`docs/`](../README.md) (commands from the **repository root**; one **`PROFILE`** for steps 1–3 — see [lab conventions](../../README.md#lab-conventions)).

## Runbooks

| Step | Guide | Topic |
|------|-------|--------|
| 1 | [`../01-kubernetes/README.md`](../01-kubernetes/README.md) | KinD cluster, topology labels |
| 2 | [`../02-mission-control/README.md`](../02-mission-control/README.md) | Helm install, upgrade, UI |
| 3 | [`../03-hcd/README.md`](../03-hcd/README.md) | HCD deploy, upgrade |
| 4 | [`../04-cql/README.md`](../04-cql/README.md) | CQL console and `cqlsh` |
| 5 | [`../05-data-api/README.md`](../05-data-api/README.md) | Data API gateway |
| 6 | [`../06-monitoring/README.md`](../06-monitoring/README.md) | Observability, Grafana |

## Deep dives

- [`deployment-structure.md`](deployment-structure.md) — Helm-first deployment and reconciliation flow
- [`software-components-wiring.md`](software-components-wiring.md) — component inventory and YAML wiring
- [`understanding-a-deployment-quickly.md`](understanding-a-deployment-quickly.md) — fast triage checklist

## Config assets

- [`../../kind/README.md`](../../kind/README.md) — KinD YAML profiles
- [`../../charts/mission-control/`](../../charts/mission-control/) — Helm `values.yaml` + `overrides.yaml`
- [`../../charts/hcd/`](../../charts/hcd/) — `MissionControlCluster` examples
