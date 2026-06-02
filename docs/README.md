# Lab runbooks

**Prerequisites**

- 📂 Run every command from the **repository root** of this clone.
- 🧭 Pick one **`PROFILE`** (`minimal`, `3-racks`, or `2-dcs`) for steps 1–3 — see [Lab conventions](../README.md#lab-conventions).

**How to read these guides**

| Symbol | Meaning |
|--------|---------|
| 🖥️ | Mission Control UI steps (try these first when both UI and CLI exist) |
| ⌨️ | CLI / `kubectl` / Helm |
| ➡️ | Next step in the lab sequence |
| ⚠️ | KinD or environment caveat |
| 💡 | Optional or alternative |
| 🔧 | Troubleshooting |

Follow in order:

1. [**Kubernetes (KinD)**](01-kubernetes.md) — cluster `mc`, topology labels  
2. [**Mission Control**](02-mission-control.md) — install, upgrade, UI  
3. [**HCD**](03-hcd.md) — `MissionControlCluster` for your `PROFILE`  
4. [**CQL (cqlsh)**](04-cql.md) — optional gateway; MC console or CLI  
5. [**Data API**](05-data-api.md) — optional HTTP gateway for `hcd-dc1`  
6. [**Monitoring**](06-monitoring.md) — Observability; optional Grafana  
7. [**Backup and restore**](07-backup-restore.md) — snapshot-based lab workflow  

Overview: [repository README](../README.md).

## Concepts

Architecture reference (not install steps): [`concepts/README.md`](concepts/README.md)
