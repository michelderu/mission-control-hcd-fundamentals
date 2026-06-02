# Monitoring — Mission Control UI and Grafana

View cluster health and metrics after steps 1–3. Optional: [CQL (step 4)](04-cql.md), [Data API (step 5)](05-data-api.md).

**Prerequisites**

- 📂 Run from the **repository root**.
- Mission Control in **`mission-control`**; HCD running in **`hcd`** (any **`PROFILE`**).

➡️ **Next:** [Backup and restore (step 7)](07-backup-restore.md)

## What is already running

The default lab install (`values.yaml` + `overrides.yaml`) deploys **Mimir**, **Loki**, **Vector aggregator**, and **Alertmanager** with embedded **MinIO**.

Grafana is **disabled** in pinned `values.yaml`. Enable it in [Grafana (optional)](#grafana-optional) when you want the Grafana UI.

## 🖥️ Mission Control UI — Observability

Built-in observability — cluster health for any topology.

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](02-mission-control.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **Observability**.

## 📊 Grafana (optional)

### ⌨️ CLI — enable

```bash
export MC_CHART=oci://registry.replicated.com/mission-control/stable/mission-control
export MC_CHART_VERSION=1.18.0

helm upgrade mission-control "$MC_CHART" \
  -f manifests/mission-control/values.yaml \
  -f manifests/mission-control/overrides.yaml \
  -f manifests/mission-control/grafana/enable-grafana.yaml \
  --namespace mission-control \
  --version "$MC_CHART_VERSION"

kubectl get pods -n mission-control | grep grafana
kubectl get svc -n mission-control | grep grafana
```

### 🖥️ Access Grafana

In one terminal (leave it running):

```bash
kubectl port-forward svc/mission-control-grafana -n mission-control 3000:80
```

Open `http://localhost:3000`. Admin credentials:

```bash
kubectl get secret mission-control-grafana -n mission-control -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl get secret mission-control-grafana -n mission-control -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Built-in Mission Control dashboards should appear under **Dashboards**. If charts are empty, check **Configuration** → **Data sources** (Mimir, Loki) and that observability pods are Ready in **`mission-control`**.

## ⌨️ Pipeline checks

```bash
kubectl get pods -n mission-control | grep -E 'mimir|loki|aggregator|grafana'
kubectl logs -n mission-control deploy/mission-control-mimir-distributor --tail=30
```

## 🔧 Troubleshooting

| Symptom | Check |
|---------|--------|
| No project in UI | `kubectl label namespace hcd mission-control.datastax.com/is-project=true` |
| Cluster missing | `kubectl get missioncontrolcluster -n hcd`; Cassandra pods Ready |
| UI Observability empty | Mimir / Vector pods in `mission-control` |
| Grafana charts empty | Data sources and observability pods Ready |

## Disable Grafana again

Omit `enable-grafana.yaml` on upgrade (see [`enable-grafana.yaml`](../manifests/mission-control/grafana/enable-grafana.yaml) comment).
