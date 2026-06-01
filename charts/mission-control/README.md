# Mission Control Helm values

**Repository root:** Helm commands in [`docs/02-mission-control/README.md`](../../docs/02-mission-control/README.md) assume you are in the clone root (`charts/mission-control/` paths are relative to it).

| File | Role |
|------|------|
| `values.yaml` | Pinned upstream chart defaults (`helm show values …`) |
| `overrides.yaml` | Lab changes: Dex, MinIO/Loki, platform `nodeSelector`s |
| `enable-grafana.yaml` | Optional: `grafana.enabled: true` + platform `nodeSelector` |

**Install and upgrade:** [`docs/02-mission-control/README.md`](../../docs/02-mission-control/README.md).  
**Monitoring (UI + Grafana):** [`docs/06-monitoring/README.md`](../../docs/06-monitoring/README.md).
