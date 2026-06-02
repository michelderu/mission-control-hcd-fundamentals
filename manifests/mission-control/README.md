# Mission Control Helm values

**Prerequisites**

- 📂 Helm commands in [`docs/02-mission-control.md`](../../docs/02-mission-control.md) assume the **repository root** (`manifests/mission-control/` paths are relative to it).

| File | Role |
|------|------|
| `values.yaml` | Pinned upstream chart defaults (`helm show values …`) |
| `overrides.yaml` | Lab changes: Dex, MinIO/Loki, platform `nodeSelector`s |
| `enable-grafana.yaml` | 💡 Optional: `grafana.enabled: true` + platform `nodeSelector` |

| Guide | Topic |
|-------|--------|
| ➡️ [`docs/02-mission-control.md`](../../docs/02-mission-control.md) | Install and upgrade |
| [`docs/06-monitoring.md`](../../docs/06-monitoring.md) | Observability and Grafana |
