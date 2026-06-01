# Lab runbooks

**Repository root:** run every command from the root of this git clone. **Topology:** pick one `PROFILE` (`minimal`, `3-racks`, or `2-dcs`) for steps 1–3 — see [Lab conventions](../README.md#lab-conventions).

Follow in order:

1. [**Kubernetes (KinD)**](01-kubernetes/README.md) — cluster `mc`, topology labels  
2. [**Mission Control**](02-mission-control/README.md) — install, upgrade, UI (profile-independent)  
3. [**HCD**](03-hcd/README.md) — `MissionControlCluster` for your `PROFILE`  
4. [**CQL (cqlsh)**](04-cql/README.md) — MC UI CQL console or CLI  
5. [**Data API**](05-data-api/README.md) — optional HTTP gateway for `hcd-dc1`  
6. [**Monitoring**](06-monitoring/README.md) — MC UI Observability; optional Grafana  

Overview: [repository README](../README.md).

## Concepts

Architecture reference: [`concepts/README.md`](concepts/README.md)
