# Concepts

Architecture and wiring reference for this lab — not install steps.

**Prerequisites**

- 📂 Step-by-step runbooks live under [`docs/`](../README.md) (commands from the **repository root**; one **`PROFILE`** for steps 1–3 — see [lab conventions](../../README.md#lab-conventions)).

## Runbooks

| Step | Guide | Topic |
|------|-------|--------|
| 1 | [`../01-kubernetes.md`](../01-kubernetes.md) | KinD cluster, topology labels |
| 2 | [`../02-mission-control.md`](../02-mission-control.md) | Helm install, upgrade, UI |
| 3 | [`../03-hcd.md`](../03-hcd.md) | HCD deploy, upgrade |
| 4 | [`../04-cql.md`](../04-cql.md) | CQL console and `cqlsh` |
| 5 | [`../05-data-api.md`](../05-data-api.md) | Data API gateway |
| 6 | [`../06-monitoring.md`](../06-monitoring.md) | Observability, Grafana |
| 7 | [`../07-backup-restore.md`](../07-backup-restore.md) | Backup and restore lab workflow |

## Deep dives

- [`deployment-structure.md`](deployment-structure.md) — Helm-first deployment and reconciliation flow
- [`software-components-wiring.md`](software-components-wiring.md) — component inventory and YAML wiring
- [`understanding-a-deployment-quickly.md`](understanding-a-deployment-quickly.md) — fast triage checklist

## Config assets

- [`../../kind/README.md`](../../kind/README.md) — KinD YAML profiles
- [`../../manifests/mission-control/`](../../manifests/mission-control/) — Helm `values.yaml` + `overrides.yaml`
- [`../../manifests/hcd/`](../../manifests/hcd/) — `MissionControlCluster` examples
