# Data API — HTTP access to HCD

Expose a **Data API** gateway for **`hcd-dc1`** ([DataStax docs](https://docs.datastax.com/en/mission-control/databases/get-started-data-api.html)).

**Prerequisites:** Run from the **repository root**. Steps 1–4 complete (HCD **Ready**; [CQL](../04-cql/README.md) optional but confirms connectivity). Works with any **`PROFILE`** — the lab manifest always targets **`hcd-dc1`**. For **`hcd-dc2`** on the `2-dcs` profile, add another gateway via the UI or a second `DataApi` CR.

**Next:** [Monitoring](../06-monitoring/README.md)

## What you deploy

| Piece | Role |
|-------|------|
| `dataApi: {}` on `MissionControlCluster` | Already in lab manifests (all profiles) |
| **`DataApi` CR** | Gateway for `hcd-dc1` — this step |

Lab manifest: [`charts/hcd/data-api/data-api-dc1.yaml`](../../charts/hcd/data-api/data-api-dc1.yaml)  
ClusterIP Service: **`lab-data-api-dc1-data-api-cip`** on port **30080**

## Enable gateway

### Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](../02-mission-control/README.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **Connect** → **APIs**.
3. **Add Gateway** → datacenter **`hcd-dc1`**, service type **clusterIP**, port **30080**, **1** replica.

### CLI

```bash
kubectl apply -f charts/hcd/data-api/data-api-dc1.yaml

kubectl get dataapi,pods,svc -n hcd | grep data
```

## Connect and test

### Port-forward

In one terminal (leave it running):

```bash
kubectl port-forward svc/lab-data-api-dc1-data-api-cip -n hcd 30080:30080
```

In-cluster (no port-forward): `http://lab-data-api-dc1-data-api-cip.hcd.svc.cluster.local:30080`

### Credentials

```bash
kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d; echo
```

Token format: `Cassandra:BASE64_USERNAME:BASE64_PASSWORD` ([HCD Data API auth](https://docs.datastax.com/en/hyper-converged-database/1.2/api-reference/dataapiclient.html#generate-token)).

### Test (`findKeyspaces`)

With the port-forward active, in a second terminal from the **repository root**:

```bash
DATA_API_USER=$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d)
DATA_API_PASS=$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d)
TOKEN="Cassandra:$(printf '%s' "$DATA_API_USER" | base64 | tr -d '\n'):$(printf '%s' "$DATA_API_PASS" | base64 | tr -d '\n')"

curl -sS -L -X POST "http://127.0.0.1:30080/v1" \
  -H "Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"findKeyspaces": {}}'
```

A JSON response listing keyspaces (possibly empty) confirms the gateway and credentials work. See [List keyspaces](https://docs.datastax.com/en/hyper-converged-database/1.2/api-reference/admin-methods/list-keyspaces.html).

## Remove

### CLI

```bash
kubectl delete -f charts/hcd/data-api/data-api-dc1.yaml
```

You can also delete the gateway from **Connect** → **APIs** in the Mission Control UI.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| No `DataApi` CRD | `kubectl api-resources \| grep -i dataapi` |
| Wrong DC | `spec.cassandraDatacenterRef.name` is `hcd-dc1` and DC exists: `kubectl get cassandradatacenter -n hcd` |
| Auth errors | Secret `hcd-superuser` in namespace `hcd` |
| Gateway not ready | `kubectl get pods -n hcd \| grep data-api` |
