# Installing, updating, and upgrading Mission Control

Install Mission Control on the KinD cluster from [Kubernetes setup (step 1)](01-kubernetes.md) using **embedded MinIO**, pinned Helm values, and platform `nodeSelector`s.

**Prerequisites**

- 📂 Run from the **repository root**.
- KinD cluster **`mc`** is running ([Kubernetes setup](01-kubernetes.md)).

➡️ **Next:** [HCD install (step 3)](03-hcd.md) — use the same **`PROFILE`** as KinD.

## What you install

- Mission Control operator, UI, APIs
- **Dex** (local static login in this lab)
- **cert-manager** (TLS for MC and database certs)
- **Loki / Mimir** with in-cluster **MinIO** (`mimir.minio.enabled: true`)
- Operators pinned to `mission-control.datastax.com/role=platform` nodes

Chart files: `manifests/mission-control/values.yaml` (pinned upstream) + `manifests/mission-control/overrides.yaml` (lab changes).

## Pin chart version and values

```bash
export MC_CHART=oci://registry.replicated.com/mission-control/stable/mission-control
export MC_CHART_VERSION=1.18.0

helm show values "$MC_CHART" --version "$MC_CHART_VERSION" > manifests/mission-control/values.yaml
```

Keep environment-specific settings in `manifests/mission-control/overrides.yaml` only (Dex, Loki S3/MinIO, `nodeSelector` for platform nodes).

**Alternative:** [DataStax sample values](https://docs.datastax.com/en/mission-control/install/_attachments/sample-values.yaml) + [install docs](https://docs.datastax.com/en/mission-control/install/install-mc-helm.html) (GCS-backed observability; this lab uses MinIO).

> ⚠️ **MinIO:** Loki uses `<release>-minio.<namespace>.svc.cluster.local:9000` and Secret `mission-control-minio` (`rootUser` / `rootPassword`). Do not trim `loki.loki.schemaConfig.configs` in overrides — Helm replaces whole lists.

## Registry login

```bash
cp .env.example .env   # set MC_REGISTRY_USERNAME, MC_REGISTRY_PASSWORD

helm registry login registry.replicated.com \
  --username "$(sed -n 's/^MC_REGISTRY_USERNAME=//p' .env)" \
  --password "$(sed -n 's/^MC_REGISTRY_PASSWORD=//p' .env)"
```

## Install cert-manager

Required before Mission Control.

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "v1.16.1" \
  --set crds.enabled=true \
  --set 'extraArgs[0]=--enable-certificate-owner-ref=true'

kubectl get pods -n cert-manager
```

## Dex login (optional override)

Default lab user in `overrides.yaml`:

- `mission-control@example.com` / `cassandra`

Custom password:

```bash
echo 'your-password-here' | htpasswd -BinC 10 admin | cut -d: -f2
```

Set under `dex.config.staticPasswords` in `manifests/mission-control/overrides.yaml`.

## Install Mission Control

```bash
helm install mission-control "$MC_CHART" \
  -f manifests/mission-control/values.yaml \
  -f manifests/mission-control/overrides.yaml \
  --namespace mission-control \
  --create-namespace \
  ${MC_CHART_VERSION:+--version "$MC_CHART_VERSION"}
```

Verify:

```bash
helm list -n mission-control
watch kubectl get pods -n mission-control -o wide --sort-by=.spec.nodeName
```

Platform pods should land on workers with `role=platform`. A healthy Mission Control system looks like:

```text
NAME                                                        READY   STATUS      RESTARTS       AGE    IP            NODE         NOMINATED NODE   READINESS GATES
mission-control-grafana-6678bc699d-4wccf                    3/3     Running     0              19m    10.244.1.26   mc-worker    <none>           <none>
mission-control-k8ssandra-operator-85fbf7bb87-b9h79         1/1     Running     0              148m   10.244.1.9    mc-worker    <none>           <none>
replicated-f65f69fd5-7tld5                                  1/1     Running     0              148m   10.244.1.4    mc-worker    <none>           <none>
mission-control-aggregator-0                                1/1     Running     0              148m   10.244.1.18   mc-worker    <none>           <none>
mission-control-cass-operator-5fd4999d77-sb9bb              1/1     Running     0              148m   10.244.1.8    mc-worker    <none>           <none>
mission-control-crd-patcher-gcpb4                           0/1     Completed   0              19m    10.244.1.25   mc-worker    <none>           <none>
loki-read-d48c8c6cb-92w7l                                   1/1     Running     0              148m   10.244.1.14   mc-worker    <none>           <none>
mission-control-crd-upgrader-6bchl                          0/1     Completed   0              19m    10.244.1.24   mc-worker    <none>           <none>
mission-control-mimir-ingester-2                            1/1     Running     0              148m   10.244.1.12   mc-worker    <none>           <none>
mission-control-operator-5b9fc8d6bf-hv6kh                   1/1     Running     0              148m   10.244.1.10   mc-worker    <none>           <none>
mission-control-mimir-store-gateway-0                       1/1     Running     0              148m   10.244.1.19   mc-worker    <none>           <none>
mission-control-mimir-query-scheduler-99fdc87d-rbfrx        1/1     Running     0              148m   10.244.1.17   mc-worker    <none>           <none>
mission-control-mimir-alertmanager-0                        1/1     Running     0              148m   10.244.1.20   mc-worker    <none>           <none>
mission-control-mimir-querier-7846798965-lgr78              1/1     Running     0              148m   10.244.1.15   mc-worker    <none>           <none>
mission-control-mimir-distributor-65495575c4-cnzgn          1/1     Running     0              148m   10.244.1.16   mc-worker    <none>           <none>
mission-control-mimir-gateway-58ff6bd844-hsdmg              1/1     Running     0              148m   10.244.1.13   mc-worker    <none>           <none>
mission-control-mimir-ingester-0                            1/1     Running     0              148m   10.244.2.15   mc-worker2   <none>           <none>
mission-control-mimir-query-frontend-57d5c76f8d-z4gvr       1/1     Running     0              148m   10.244.2.20   mc-worker2   <none>           <none>
loki-backend-0                                              1/1     Running     0              148m   10.244.2.13   mc-worker2   <none>           <none>
loki-write-0                                                1/1     Running     0              148m   10.244.2.24   mc-worker2   <none>           <none>
mission-control-mimir-overrides-exporter-66578c7ffc-zcm6w   1/1     Running     0              148m   10.244.2.19   mc-worker2   <none>           <none>
mission-control-mimir-compactor-0                           1/1     Running     0              148m   10.244.2.12   mc-worker2   <none>           <none>
mission-control-mimir-querier-7846798965-rpwsk              1/1     Running     0              148m   10.244.2.21   mc-worker2   <none>           <none>
mission-control-mimir-ingester-1                            1/1     Running     0              148m   10.244.2.14   mc-worker2   <none>           <none>
mission-control-mimir-query-scheduler-99fdc87d-dcql6        1/1     Running     0              148m   10.244.2.23   mc-worker2   <none>           <none>
mission-control-loki-gateway-5fd99d7dc-2htp7                1/1     Running     0              148m   10.244.2.18   mc-worker2   <none>           <none>
mission-control-mimir-ruler-6c966b6948-c2m9d                1/1     Running     0              148m   10.244.2.22   mc-worker2   <none>           <none>
mission-control-kube-state-metrics-67665dd795-ldrjm         1/1     Running     0              148m   10.244.2.4    mc-worker2   <none>           <none>
mission-control-minio-7d69ddc8fd-gs9jl                      1/1     Running     0              148m   10.244.2.11   mc-worker2   <none>           <none>
mission-control-dex-6c8c8dd5f4-622mc                        1/1     Running     1 (148m ago)   148m   10.244.2.17   mc-worker2   <none>           <none>
mission-control-ui-f8d4df66f-9wsj7                          1/1     Running     0              148m   10.244.2.16   mc-worker2   <none>           <none>
mission-control-mimir-make-minio-buckets-5.4.0-nfls6        0/1     Completed   0              148m   10.244.10.3   mc-worker7   <none>           <none>
```

## Access the UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080`.
2. Log in with Dex credentials from overrides (`mission-control@example.com` / `cassandra` in the default lab).

Use this port-forward in later steps (HCD, CQL, Data API, Observability) whenever a guide says **Mission Control login**.

## Upgrade Mission Control

After editing `overrides.yaml` or refreshing pinned `values.yaml`:

```bash
helm upgrade mission-control "$MC_CHART" \
  -f manifests/mission-control/values.yaml \
  -f manifests/mission-control/overrides.yaml \
  --namespace mission-control \
  ${MC_CHART_VERSION:+--version "$MC_CHART_VERSION"}
```

## Uninstall Mission Control (keep KinD)

Removes the Mission Control namespace and MC PVCs. **Does not** remove the HCD namespace (`hcd`).

```bash
helm uninstall mission-control -n mission-control
kubectl delete namespace mission-control
```

Reinstall with **Install Mission Control** above. HCD clusters in other namespaces remain until you delete them ([HCD guide](03-hcd.md)).

## Deeper reference

- [`concepts/deployment-structure.md`](concepts/deployment-structure.md)
- [`concepts/software-components-wiring.md`](concepts/software-components-wiring.md)
