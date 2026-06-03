# Restore DC1 and rebuild corrupt DC2 (lab MOP)

Lab walkthrough for **`PROFILE=2-dcs`** when **DC1** is recovered from Medusa backup and **DC2 is corrupt** (data must not be trusted). The flow follows [Rebuild a failed datacenter](https://docs.datastax.com/en/mission-control/administration/control-plane/rebuild-failed-datacenter.html), with **Phase 1** adding a Medusa restore on the survivor.

**Prerequisites:** [Backup and restore](07-backup-restore.md) completed (`lab_restore` with `dc1:3, dc2:3`, valid DC1 backup).

> ⚠️ **Data loss on DC2:** The official procedure **permanently deletes** all DC2 PVCs and data when you remove the datacenter from `MissionControlCluster`. Run only in a lab or when DC2 is truly unrecoverable.

> ⚠️ **Pause application writers** for user keyspaces before step 2.

---

## Scenario and name mapping

| Role | Cassandra ring name | `CassandraDatacenter` CR | Notes |
|------|---------------------|--------------------------|--------|
| Survivor (restore target) | `dc1` | `hcd-dc1` | Authoritative after backup restore |
| Failed (corrupt) | `dc2` | `hcd-dc2` | Removed from replication, then from manifest, then re-added empty |

| Official guide step | This MOP |
|---------------------|----------|
| Remove replication to failed DC | Step 2 (before restore) |
| Restore / survivor data | Phase 1: Medusa on `hcd-dc1` |
| Remove failed DC from `MissionControlCluster` | Phase 2 step 8 |
| Re-add datacenter | Phase 2 step 10 |
| Repair system keyspaces on survivor | Phase 2 step 12 |
| Replicate data (`ALTER` + `K8ssandraTask`) | Phase 2 steps 13–15 |

If **all** datacenters failed, use [restore from backup](https://docs.datastax.com/en/mission-control/administration/control-plane/restore.html) instead of this MOP.

---

## Architecture

```
Step 2: ALTER KEYSPACE → dc1 only
Phase 1: Medusa restore → DC1 (authoritative)
Phase 2: Remove DC2 from MCC → empty DC2 → stream from DC1
┌────────┐  backup   ┌────────┐  wipe &    ┌────────┐
│ Backup │ ────────► │  DC1   │  re-add    │  DC2   │
└────────┘           │ (dc1)  │ ─────────► │ (dc2)  │
                     └────────┘  K8ssandraTask rebuild
```

---

## Prerequisites

* Valid DC1 backup; Mission Control and namespace `hcd` healthy.
* `kubectl` can change resources in `hcd`.
* `cqlsh` / `ALTER KEYSPACE` via `hcd-superuser`.
* Repo root; **`PROFILE=2-dcs`** originally applied from `manifests/hcd/mission-control-cluster-2-dcs.yaml`.

**Environment variables:**

```bash
NAMESPACE="hcd"
CLUSTER_NAME="hcd"

DC1_DATACENTER_CR="hcd-dc1"
DC2_DATACENTER_CR="hcd-dc2"
SOURCE_DC="dc1"
TARGET_DC="dc2"

BACKUP_NAME="backup-2026-06-02t10-40-43-610z"   # kubectl get medusabackups -n hcd
RESTORE_JOB_NAME="restore-dc1-$(date +%Y%m%d)"

YOUR_KEYSPACE="lab_restore"
YOUR_TABLE="users"

# K8ssandraTask metadata.name: RFC 1123 — no underscores (lab_restore → lab-restore)
REBUILD_TASK_NAME="rebuild-${TARGET_DC}-$(echo "${YOUR_KEYSPACE}" | tr '_' '-')"
```

---

## Process overview

```
PHASE 1 — Survivor restore (DC2 corrupt; isolate replication first)
 1. Verify backup
 2. Remove DC2 from user keyspace replication (dc1 only)
 3. Prepare DC1
 4. MedusaRestoreJob on hcd-dc1
 5. Monitor restore
 6. Verify DC1 health
 7. Validate DC1 data

PHASE 2 — Rebuild failed DC2 (DataStax failed-datacenter path)
 8. Remove hcd-dc2 from MissionControlCluster
 9. Verify DC2 resources gone; assassinate ghosts if needed
10. Re-add hcd-dc2 (full 2-dcs manifest)
11. Wait for DC2 pods Running
12. Repair system keyspaces on DC1
13. Restore replication (dc1 + dc2) on user keyspace
14. K8ssandraTask rebuild (stream per keyspace)
15. Monitor streaming
16. Verify DC2 health and data
17. Optional cleanup on DC2
18. User keyspace repair (Mission Control / Reaper)
19. Final validation
```

---

## PHASE 1: RESTORE DC1 (DC2 isolated)

### Step 1: Verify backup exists

```bash
kubectl get medusabackups.medusa.k8ssandra.io -n ${NAMESPACE}
kubectl get medusabackups.medusa.k8ssandra.io ${BACKUP_NAME} -n ${NAMESPACE} -o yaml
```

**✓ Validation:** Backup finished successfully.

> ⚠️ **STOP** if the backup is invalid.

---

### Step 2: Remove corrupt DC2 from replication (before restore)

Per DataStax, drop the failed datacenter from **user keyspaces** on the survivor **before** restore so quorum paths and read repair cannot use corrupt DC2 replicas.

```bash
DC1_SEED_POD=$(kubectl get pods -n ${NAMESPACE} \
  -l "cassandra.datastax.com/datacenter=${DC1_DATACENTER_CR},app.kubernetes.io/name=cassandra" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

CQL_USER=$(kubectl get secret hcd-superuser -n ${NAMESPACE} -o jsonpath='{.data.username}' | base64 -d)
CQL_PASSWD=$(kubectl get secret hcd-superuser -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "DESCRIBE KEYSPACE ${YOUR_KEYSPACE};"

kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "ALTER KEYSPACE ${YOUR_KEYSPACE} WITH replication = {'class': 'NetworkTopologyStrategy', '${SOURCE_DC}': 3};"
```

You may see a warning to run `nodetool repair -pr`. Ignore it when RF on `dc1` is unchanged.

> 💡 **Replication vs schema:** This step stops **data** for `${YOUR_KEYSPACE}` from using DC2 replicas (quorum, read repair, new writes). It does **not** block **DDL** — while DC2 pods are still in the cluster, `CREATE`/`ALTER` on user keyspaces still propagates to DC2 nodes via cluster-wide schema migration. Avoid new DDL on user keyspaces until Phase 2 completes if you want a simple timeline; corrupt DC2 **data** is still removed in steps 8–10.

**✓ Validation:** `DESCRIBE KEYSPACE` lists only `dc1` in the replication strategy.

---

### Step 3: Prepare DC1 for restore

```bash
kubectl get cassandradatacenter ${DC1_DATACENTER_CR} -n ${NAMESPACE}
kubectl get pods -n ${NAMESPACE} -l cassandra.datastax.com/datacenter=${DC1_DATACENTER_CR}
```

**✓ Validation:** DC1 pods are `Running`.

---

### Step 4: Create and apply DC1 restore job

Medusa restores **DC1 only**; it does not fix DC2.

```bash
kubectl apply --dry-run=client -f - <<EOF
apiVersion: medusa.k8ssandra.io/v1alpha1
kind: MedusaRestoreJob
metadata:
  name: ${RESTORE_JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  cassandraDatacenter: ${DC1_DATACENTER_CR}
  backup: ${BACKUP_NAME}
EOF

kubectl apply -f - <<EOF
apiVersion: medusa.k8ssandra.io/v1alpha1
kind: MedusaRestoreJob
metadata:
  name: ${RESTORE_JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  cassandraDatacenter: ${DC1_DATACENTER_CR}
  backup: ${BACKUP_NAME}
EOF
```

**✓ Validation:** `spec.cassandraDatacenter` is `hcd-dc1` (CR name), not `dc1`.

---

### Step 5: Monitor DC1 restore progress

```bash
kubectl get medusarestorejob ${RESTORE_JOB_NAME} -n ${NAMESPACE} -w
kubectl wait --for=condition=complete medusarestorejob/${RESTORE_JOB_NAME} -n ${NAMESPACE} --timeout=7200s
```

**✓ Validation:** Restore job completes.

---

### Step 6: Verify DC1 cluster health

```bash
kubectl get cassandradatacenter ${DC1_DATACENTER_CR} -n ${NAMESPACE}
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status
```

**✓ Validation:** DC1 nodes are `UN`; `nodetool status` shows only datacenter `dc1` for the restored keyspace ownership (DC2 may still appear in gossip until Phase 2 tear-down).

---

### Step 7: Validate DC1 data restored

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "SELECT * FROM ${YOUR_KEYSPACE}.${YOUR_TABLE} LIMIT 5;"
```

**✓ Validation:** Expected rows on DC1.

---

## PHASE 2: REBUILD CORRUPT DC2

### Step 8: Remove failed DC2 from `MissionControlCluster`

Per [Terminate a datacenter](https://docs.datastax.com/en/mission-control/administration/control-plane/remove-db-datacenter.html). **Step 2 must be complete** — termination fails if user keyspaces still replicate to `dc2`.

Merge-patch `.spec.k8ssandra.cassandra.datacenters` to the survivor-only list (drops `hcd-dc2`):

```bash
kubectl patch missioncontrolcluster ${CLUSTER_NAME} -n ${NAMESPACE} \
  --type merge \
  --patch-file /dev/stdin <<'EOF'
spec:
  k8ssandra:
    cassandra:
      datacenters:
        - metadata:
            name: hcd-dc1
          datacenterName: dc1
          size: 3
          racks:
            - name: rack1
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack1
            - name: rack2
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack2
            - name: rack3
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack3
EOF
```

> 💡 Add `--dry-run=client` before `--patch-file` to validate the patch without applying.

Watch termination:

```bash
kubectl get k8ssandracluster ${CLUSTER_NAME} -n ${NAMESPACE}
kubectl get cassandradatacenter ${DC2_DATACENTER_CR} -n ${NAMESPACE}
```

> ⚠️ **Data loss:** Operators remove the DC2 `CassandraDatacenter`, StatefulSets, and **data PVCs**.

**✓ Validation:** Patch succeeds with no `ERROR` on `K8ssandraCluster`; finish resource checks in step 9.

---

### Step 9: Verify DC2 removal; assassinate if needed

```bash
kubectl get cassandradatacenter,pvc,sts,pod -n ${NAMESPACE} | grep -E 'dc2|hcd-dc2' || true
```

**✓ Validation:** No DC2 `CassandraDatacenter`, STS, pods, or data PVCs remain.

If DC2 nodes still appear in gossip:

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status
# For each stale DC2 IP still listed:
# kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool assassinate <dc2-pod-ip>
```

If a `CassandraDatacenter` CR remains:

```bash
kubectl delete cassandradatacenter ${DC2_DATACENTER_CR} -n ${NAMESPACE} --ignore-not-found
```

Re-check until only `dc1` appears in `nodetool status`.

---

### Step 10: Re-add DC2 to `MissionControlCluster`

Per [Re-add the datacenter](https://docs.datastax.com/en/mission-control/administration/control-plane/rebuild-failed-datacenter.html#re-add-the-datacenter). Merge-patch the full **2-dcs** `datacenters` list (same topology as `manifests/hcd/mission-control-cluster-2-dcs.yaml`):

> 💡 **Fresh PVCs, not corrupt data:** Step 8 should have deleted DC2 data PVCs. Step 10 creates a new `CassandraDatacenter`, StatefulSets, pods, and **new empty** volumes. This does not intentionally remount old corrupt disks. If step 9 left DC2 PVCs behind, a pod might bind to stale storage — confirm before patching:
>
> ```bash
> kubectl get pvc -n ${NAMESPACE} | grep -E 'dc2|hcd-dc2' || echo "no DC2 PVCs (OK to continue)"
> ```
>
> User data on DC2 comes from **rebuild/streaming** (steps 14–15), not from the old PVCs.

```bash
kubectl patch missioncontrolcluster ${CLUSTER_NAME} -n ${NAMESPACE} \
  --type merge \
  --patch-file /dev/stdin <<'EOF'
spec:
  k8ssandra:
    cassandra:
      datacenters:
        - metadata:
            name: hcd-dc1
          datacenterName: dc1
          size: 3
          racks:
            - name: rack1
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack1
            - name: rack2
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack2
            - name: rack3
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc1
                topology.kubernetes.io/zone: rack3
        - metadata:
            name: hcd-dc2
          datacenterName: dc2
          size: 3
          racks:
            - name: rack1
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc2
                topology.kubernetes.io/zone: rack1
            - name: rack2
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc2
                topology.kubernetes.io/zone: rack2
            - name: rack3
              nodeAffinityLabels:
                mission-control.datastax.com/role: database
                topology.kubernetes.io/region: dc2
                topology.kubernetes.io/zone: rack3
EOF
```

> 💡 Add `--dry-run=client` before `--patch-file` to validate without applying.

```bash
kubectl get cassandradatacenter ${DC2_DATACENTER_CR} -n ${NAMESPACE}
```

**✓ Validation:** `CassandraDatacenter` `${DC2_DATACENTER_CR}` is created and becomes ready (step 11).

---

### Step 11: Wait for new DC2 pods

```bash
kubectl get cassandradatacenter,sts,pod -n ${NAMESPACE} -l cassandra.datastax.com/datacenter=${DC2_DATACENTER_CR}
kubectl wait --for=condition=ready cassandradatacenter/${DC2_DATACENTER_CR} -n ${NAMESPACE} --timeout=1800s
```

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status ${YOUR_KEYSPACE}
```

**✓ Validation:** All DC2 pods are `Running`. In `nodetool status` (with a keyspace name), new DC2 nodes show **Up/Normal (`UN`)** but only **a few hundred KiB** of load — expected. Until step 13 restores `${TARGET_DC}` in the keyspace replication map, **`${YOUR_KEYSPACE}` does not yet treat the new datacenter as a replica** (you may also see Cassandra’s note that non-system keyspaces differ in replication settings). DC2 is empty on disk until **step 14** streams data from DC1.

---

### Step 12: Repair system keyspaces on DC1

Official step before streaming user data to the empty DC:

```bash
for ks in system_auth dse_leases system_distributed dse_security dse_system; do
  for pod in $(kubectl get pods -n ${NAMESPACE} \
    -l cassandra.datastax.com/datacenter=${DC1_DATACENTER_CR},app.kubernetes.io/name=cassandra \
    -o jsonpath='{.items[*].metadata.name}'); do
    echo "== ${pod} ${ks} =="
    kubectl exec -n ${NAMESPACE} ${pod} -c cassandra -- nodetool repair -pr ${ks}
  done
done
```

**✓ Validation:** Each repair finishes without fatal errors.

---

### Step 13: Add DC2 back to user keyspace replication

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "ALTER KEYSPACE ${YOUR_KEYSPACE} WITH replication = {'class': 'NetworkTopologyStrategy', '${SOURCE_DC}': 3, '${TARGET_DC}': 3};"
```

Cassandra may warn about `nodetool repair -pr`; streaming (step 14) and repair (step 18) address consistency.

**✓ Validation:** `DESCRIBE KEYSPACE` shows `dc1` and `dc2`.

---

### Step 14: Stream data with `K8ssandraTask`

Use **`K8ssandraTask`** (operator creates `CassandraTask` children). Do not run `nodetool rebuild` manually.

> 💡 **`metadata.name` must not contain `_`** (Kubernetes RFC 1123). Use `${REBUILD_TASK_NAME}` (for example `rebuild-dc2-lab-restore`). `args.keyspace_name` stays the real CQL name (`lab_restore`).

> 💡 **`spec.datacenters` uses the `CassandraDatacenter` CR name** (`hcd-dc2`), not the Cassandra ring name (`dc2`). `args.source_datacenter` uses the **ring** name (`dc1`). `unknown datacenters: dc2` means you used the ring name in `spec.datacenters`.

```bash
kubectl delete k8ssandratask ${REBUILD_TASK_NAME} -n ${NAMESPACE} --ignore-not-found

kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: K8ssandraTask
metadata:
  name: ${REBUILD_TASK_NAME}
  namespace: ${NAMESPACE}
spec:
  cluster:
    name: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
  dcConcurrencyPolicy: Forbid
  datacenters:
    - ${DC2_DATACENTER_CR}
  template:
    concurrencyPolicy: Allow
    maxConcurrentPods: 1
    jobs:
      - name: rebuild-keyspace
        command: rebuild
        args:
          source_datacenter: ${SOURCE_DC}
          keyspace_name: ${YOUR_KEYSPACE}
EOF
```

| Field | Value |
|-------|--------|
| `metadata.name` | `${REBUILD_TASK_NAME}` (hyphens only, e.g. `rebuild-dc2-lab-restore`) |
| `spec.datacenters` | `${DC2_DATACENTER_CR}` (`hcd-dc2` — **CR** name, not `dc2`) |
| `args.source_datacenter` | `${SOURCE_DC}` (`dc1` — Cassandra **ring** name) |
| `args.keyspace_name` | `${YOUR_KEYSPACE}` (CQL name; underscores OK) |

Repeat for each additional user keyspace (set a new `${REBUILD_TASK_NAME}` per keyspace).

---

### Step 15: Monitor streaming

```bash
kubectl describe k8ssandratask ${REBUILD_TASK_NAME} -n ${NAMESPACE}
kubectl get k8ssandratask ${REBUILD_TASK_NAME} -n ${NAMESPACE} -w
kubectl get cassandratask -n ${NAMESPACE}
```

```bash
DC2_SEED_POD=$(kubectl get pods -n ${NAMESPACE} \
  -l "cassandra.datastax.com/datacenter=${DC2_DATACENTER_CR},app.kubernetes.io/name=cassandra" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

kubectl logs -f ${DC2_SEED_POD} -n ${NAMESPACE} -c server-system-logger | grep -E -i 'rebuild|stream|finished'
```

Optional progress on DC1 ([official `netstats` pattern](https://docs.datastax.com/en/mission-control/administration/control-plane/rebuild-failed-datacenter.html)):

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool netstats | \
  awk '/\s+\/([0-9]{1,3}\.){3}[0-9]|Receiving/ { if (NF == 1) host=$1; else print host " : " $11/$4*100 "%\t" $11/1024/1024/1024 "/" $4/1024/1024/1024 "GB";}' | sort -n
```

**✓ Validation:** No `Invalid` / `unknown datacenters` condition; `status.datacenters.${DC2_DATACENTER_CR}` shows each DC2 pod `COMPLETED` (for example `3` on **2-dcs**).

---

### Step 16: Verify DC2 health and data

```bash
kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status
kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "SELECT * FROM ${YOUR_KEYSPACE}.${YOUR_TABLE} LIMIT 5;"

kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "CONSISTENCY LOCAL_QUORUM; SELECT COUNT(*) FROM ${YOUR_KEYSPACE}.${YOUR_TABLE};"
kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "CONSISTENCY LOCAL_QUORUM; SELECT COUNT(*) FROM ${YOUR_KEYSPACE}.${YOUR_TABLE};"
```

**✓ Validation:** All nodes `UN`; row counts match.

---

### Step 17: Optional — cleanup on DC2

```bash
kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: CassandraTask
metadata:
  name: cleanup-dc2-post-rebuild
  namespace: ${NAMESPACE}
spec:
  datacenter:
    name: ${DC2_DATACENTER_CR}
    namespace: ${NAMESPACE}
  jobs:
    - name: cleanup-dc2
      command: cleanup
EOF

kubectl get cassandratask cleanup-dc2-post-rebuild -n ${NAMESPACE}
```

---

### Step 18: User keyspace repair (Mission Control / Reaper)

Do not use `CassandraTask` with `command: repair`.

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. **Home** → **`hcd`** → **Repairs** → **Run repair**.
2. **Keyspace:** `${YOUR_KEYSPACE}`; **Parallelism:** `DATACENTER_AWARE`; **Repair threads:** `1`.

**✓ Validation:** Repair succeeds in the UI.

---

### Step 19: Final validation

```bash
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool describering ${YOUR_KEYSPACE}
```

Update application contact points to include DC2 ([official next steps](https://docs.datastax.com/en/mission-control/administration/control-plane/rebuild-failed-datacenter.html#next-steps)).

---

## Rollback

**Restore failed:** `kubectl delete medusarestorejob ${RESTORE_JOB_NAME} -n ${NAMESPACE}` — fix backup/Medusa, retry from step 4. If you altered replication in step 2, restore RF when aborting: `ALTER KEYSPACE … 'dc1': 3, 'dc2': 3`.

**Rebuild failed:** `kubectl delete k8ssandratask ${REBUILD_TASK_NAME} -n ${NAMESPACE}`. If DC2 is inconsistent, repeat Phase 2 from step 8 (tear-down and re-add).

---

## See also

* [Rebuild a failed datacenter](https://docs.datastax.com/en/mission-control/administration/control-plane/rebuild-failed-datacenter.html)
* [Backup and restore](07-backup-restore.md)
* `manifests/hcd/mission-control-cluster-2-dcs.yaml` — optional equivalent to step 10 patch (`kubectl apply -f …`)
* `manifests/hcd/mission-control-cluster-dc1-only.yaml` — optional equivalent to step 8 patch (`kubectl apply -f …`)
