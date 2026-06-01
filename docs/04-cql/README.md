# CQL — connect with cqlsh

Run **CQL** against HCD via an optional **CQL gateway** (`CqlConnectivity`), the Mission Control **CQL console**, or **`cqlsh`** on the CLI ([DataStax CQL console](https://docs.datastax.com/en/mission-control/databases/use-cql-console.html)).

**Prerequisites**

- 📂 Run from the **repository root**.
- Steps 1–3 complete; Cassandra pods **Ready** in namespace **`hcd`**.
- Any **`PROFILE`** (`minimal`, `3-racks`, `2-dcs`).

➡️ **Next (optional):** [Data API (step 5)](../05-data-api/README.md) · [Monitoring (step 6)](../06-monitoring/README.md)

## How you can connect

| Method | What it is | Lab default |
|--------|------------|-------------|
| **Headless CQL service** | `hcd-hcd-dc1-service` on port **9042** | Always present after HCD install |
| **CQL gateway** | `CqlConnectivity` CR → **cql-router** (LoadBalancer or Ingress) | 💡 Optional — create below |
| **CQL console** | Embedded `cqlsh` in the MC UI | Uses **cqlsh-pod** (auto-created) |
| **CLI `cqlsh`** | `kubectl exec` into **cqlsh-pod** or a Cassandra pod | See [Connect with cqlsh](#connect-with-cqlsh) |

**Do you need a gateway?** No — for the 🖥️ **CQL console**, **cqlsh-pod**, or `kubectl exec` you can use the headless service (`hcd-hcd-dc1-service:9042`) inside the cluster.

**Why add one?** A **CQL gateway** runs **cql-router** pods in front of the datacenter: stable contact points for drivers, optional **TLS** at the router, and (with **Ingress**) a **secure connect bundle** for clients outside Kubernetes.

| Gateway type | What it does | Typical use |
|--------------|--------------|-------------|
| **LoadBalancer** | External IP → **cql-router** on port **9042** | Simple `EXTERNAL-IP:9042` access; needs a LoadBalancer provider |
| **Ingress** | Hostname (`dnsBaseName`) → **cql-router** | TLS, DNS, secure connect bundle from the UI |

> ⚠️ **KinD:** LoadBalancer `EXTERNAL-IP` often stays `<pending>` without [MetalLB](https://kind.sigs.k8s.io/docs/user/loadbalancer/) or similar. Use the headless service or 🖥️ CQL console instead.

## Create a CQL gateway (optional)

A **`CqlConnectivity`** resource deploys **cql-router** and exposes port **9042**. This is separate from **Connect** → **APIs** ([Data API](../05-data-api/README.md)).

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](../02-mission-control/README.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **Connect**.
3. Open **CQL** (active CQL gateways).
4. **Add Gateway** → datacenter **`hcd-dc1`**.
5. Choose **LoadBalancer** or **Ingress**:
   - **LoadBalancer** — `size` **1**, native port **9042**.
   - **Ingress** — set `dnsBaseName` and `size` per your ingress controller; download the secure connect bundle when ready ([release notes](https://docs.datastax.com/en/mission-control/release-notes/release-notes.html)).

### ⌨️ CLI

```bash
kubectl apply -f charts/hcd/cql/cql-connectivity-dc1.yaml

kubectl get cqlconnectivity -n hcd
kubectl get pods,svc -n hcd | grep -E 'cql-router|cql-connectivity|lab-cql'
```

When the LoadBalancer has an **EXTERNAL-IP**, connect with `cqlsh` or a driver on that address and port **9042** using `hcd-superuser` credentials.

```bash
kubectl delete -f charts/hcd/cql/cql-connectivity-dc1.yaml
```

You can also remove the gateway from **Connect** → **CQL** in the UI.

Reference: [`CqlConnectivity` CR](https://docs.datastax.com/en/mission-control/crd-reference/missioncontrolcluster-v1.14.0.html) (`missioncontrol.datastax.com/v1alpha1`).

## Credentials and services

Secret **`hcd-superuser`** (from `superuserSecretRef` in the lab HCD manifests). The default `cassandra` user is disabled when auth is enabled.

```bash
kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d; echo
```

| Datacenter | Headless service (port 9042) |
|------------|------------------------------|
| `hcd-dc1` | `hcd-hcd-dc1-service` |
| `hcd-dc2` (`2-dcs` only) | `hcd-hcd-dc2-service` |

## Connect with cqlsh

### 🖥️ Mission Control UI — CQL console

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](../02-mission-control/README.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **CQL console** (not **Connect** → **CQL** gateways).
3. Select a datacenter (`hcd-dc1`; on **`2-dcs`**, choose `hcd-dc2` for the second DC).
4. Enter **username** and **password** from `hcd-superuser`.

Mission Control deploys a **`cqlsh-pod`** per cluster in namespace **`hcd`**. On **`2-dcs`**, expect pods such as `hcd-hcd-dc1-cqlsh-…` and `hcd-hcd-dc2-cqlsh-…`.

### ⌨️ CLI

List Ready database pods: `kubectl get pods -n hcd -l cassandra.datastax.com/cluster=hcd`

| `PROFILE` | Example DC1 pod | Example DC2 pod (`2-dcs`) |
|-----------|-----------------|---------------------------|
| `minimal`, `3-racks` | `hcd-dc1-rack1-sts-0` | — |
| `2-dcs` | `hcd-dc1-rack1-sts-0` | `hcd-dc2-rack1-sts-0` |

#### Option A — `cqlsh-pod` (same backend as the UI console)

```bash
CQLSH_POD=$(kubectl get pods -n hcd \
  -l app.kubernetes.io/name=cqlsh,missioncontrol.datastax.com/cluster-name=hcd,missioncontrol.datastax.com/cluster-namespace=hcd \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it "$CQLSH_POD" -n hcd -c cqlsh -- cqlsh \
  -u "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d)" \
  -p "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d)" \
  hcd-hcd-dc1-service
```

Use **`hcd-hcd-dc2-service`** for DC2 on the **`2-dcs`** profile.

#### Option B — Cassandra pod

```bash
kubectl exec -it hcd-dc1-rack1-sts-0 -n hcd -c cassandra -- cqlsh \
  -u "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d)" \
  -p "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d)"
```

Replace the pod name using `kubectl get pods -n hcd` for your **`PROFILE`**.

#### Option C — port-forward and local `cqlsh`

Through the headless service (no CQL gateway):

```bash
kubectl port-forward svc/hcd-hcd-dc1-service -n hcd 9042:9042

cqlsh -u "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d)" \
  -p "$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d)" \
  127.0.0.1 9042
```

If you created a **LoadBalancer** CQL gateway with an external IP, connect to that IP on port **9042** instead.

> 💡 **Local `cqlsh`:** requires a compatible client on your workstation ([download](https://docs.datastax.com/en/mission-control/databases/use-cql-console.html#download-the-cql-shell)). Lab clusters use **internode encryption**; if local `cqlsh` fails, use the 🖥️ console or options A/B.

## 🔧 Troubleshooting

| Symptom | Check |
|---------|--------|
| No CQL console in UI | HCD cluster Ready; project **`hcd`** labeled ([HCD install](../03-hcd/README.md)) |
| Auth failed | `hcd-superuser` exists: `kubectl get secret hcd-superuser -n hcd` |
| No `cqlsh-pod` | `kubectl get pods -n hcd \| grep cqlsh` |
| Wrong DC | Service name matches datacenter: `kubectl get svc -n hcd -l app=cassandra` |
| CQL gateway pending | `kubectl get svc -n hcd` — use headless service or CQL console on KinD |
| No `CqlConnectivity` CRD | `kubectl api-resources \| grep -i cql` |
