## Method of Procedure (MOP)

## DataStax Mission Control — Option 1: Restore DC1 and Rebuild DC2

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Option 1 Workflow                        │
└─────────────────────────────────────────────────────────────┘

Phase 1: Restore DC1 from Backup (Declared via MedusaRestoreJob)
┌──────────────┐
│   Backup     │
│   Storage    │
└──────┬───────┘
       │ Restore
       ▼
┌──────────────┐
│     DC1      │  ← Restore from backup via Medusa
│  (Primary)   │
└──────┬───────┘
       │
       │ Phase 2: Rebuild & Sync DC2 (Declared via CassandraTasks)
       │
       ▼
┌──────────────┐
│     DC2      │  ← Rebuild & targeted repair orchestrated by MC
│ (Secondary)  │
└──────────────┘

```

---

## Prerequisites

**Before Starting:**

* Valid backup exists for DC1 and is verified.
* DataStax Mission Control platform is fully healthy and active.
* `kubectl` access is configured for the target Kubernetes cluster environment.
* Maintenance window is scheduled and stakeholders are notified.
* Cross-datacenter network connectivity is verified between DC1 and DC2 pods.
* Sufficient physical storage is available in both datacenters.

**Required Environment Variables:**

```bash
# Global Cluster Configuration
NAMESPACE="hcd"

# DC1 Details
DC1_DATACENTER_NAME="hcd-dc1"
BACKUP_NAME="backup-2026-06-02t10-40-43-610z"
RESTORE_JOB_NAME="restore-dc1-$(date +%Y%m%d)"

# DC2 Details
DC2_DATACENTER_NAME="hcd-dc2"

# Application Verification Variables
YOUR_KEYSPACE="lab_restore"
YOUR_TABLE="users"
```

Run that block in your shell before steps that use `${NAMESPACE}`, `${RESTORE_JOB_NAME}`, or heredoc manifests.

---

## Process Overview

```
PHASE 1: RESTORE DC1 
1. Verify Backup          →  Confirm DC1 backup exists on storage
2. Prepare DC1            →  Verify DC1 health pre-restore
3. Apply restore job      →  Submit MedusaRestoreJob for DC1
4. Monitor DC1 restore    →  Track MedusaRestoreJob lifecycle
5. Verify DC1 health      →  Confirm DC1 cluster state post-restore
6. Validate DC1 data      →  Check DC1 data availability

PHASE 2: REBUILD & SYNC DC2
7. Prepare DC2            →  Verify DC2 cluster connectivity before rebuild
8. Apply rebuild task     →  Submit CassandraTask rebuild from DC1
9. Monitor DC2 rebuild    →  Track CassandraTask & system sidecar progress
10. Verify DC2 health     →  Confirm DC2 nodes are UN
11. Validate DC2 data     →  Check DC2 data availability & consistency
12. Post-rebuild cleanup  →  Run node cleanup via CassandraTask
13. Targeted sync repair  →  Run scoped keyspace repair in MC UI (TWCS safe)
14. Final validation      →  Confirm global cluster status = UN

```

---

## PHASE 1: RESTORE DC1 FROM BACKUP

### Step 1: Verify Backup Exists

Query the Mission Control control plane to verify the target backup object exists and is tagged valid.

```bash
# List available backups within the target namespace
kubectl get medusabackups.medusa.k8ssandra.io -n ${NAMESPACE}

# Verify status details of the specific backup object
kubectl get medusabackups.medusa.k8ssandra.io ${BACKUP_NAME} -n ${NAMESPACE} -o yaml

```

**✓ Validation:** Output reflects `status: Finished` with complete node mappings.

> ⚠️ **STOP** if validation fails. Do not proceed without a valid, control-plane-recognized backup state.

---

### Step 2: Prepare DC1 for Restore

Verify that the target datacenter pods are initialized so that Mission Control can orchestrate the rollback sequence.

```bash
# Verify the state of the CassandraDatacenter custom resource
kubectl get cassandradatacenter ${DC1_DATACENTER_NAME} -n ${NAMESPACE}

# Capture active pods belonging to DC1
kubectl get pods -n ${NAMESPACE} -l cassandra.datastax.com/datacenter=${DC1_DATACENTER_NAME}

```

**✓ Validation:** All database pods show status `Running`.

---

### Step 3: Create and apply DC1 restore job

Submit the restore job to Mission Control. The operator orchestrates the rollout on DC1 only (DC2 is rebuilt in Phase 2).

```bash
kubectl apply --dry-run=client -f - <<EOF
apiVersion: medusa.k8ssandra.io/v1alpha1
kind: MedusaRestoreJob
metadata:
  name: ${RESTORE_JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  cassandraDatacenter: ${DC1_DATACENTER_NAME}
  backup: ${BACKUP_NAME}
EOF

kubectl apply -f - <<EOF
apiVersion: medusa.k8ssandra.io/v1alpha1
kind: MedusaRestoreJob
metadata:
  name: ${RESTORE_JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  cassandraDatacenter: ${DC1_DATACENTER_NAME}
  backup: ${BACKUP_NAME}
EOF
```

**✓ Validation:** Job object created successfully (`medusarestorejob.medusa.k8ssandra.io/${RESTORE_JOB_NAME} created`). `cassandraDatacenter` must be the Mission Control DC name (`hcd-dc1`), not the Cassandra ring name (`dc1`).

---

### Step 4: Monitor DC1 restore progress

Track execution progress directly through the custom resource state tracking fields.

```bash
# Watch execution states
kubectl get medusarestorejob ${RESTORE_JOB_NAME} -n ${NAMESPACE}

# Inspect completion flags via explicit timeout block
kubectl wait --for=condition=complete medusarestorejob/${RESTORE_JOB_NAME} -n ${NAMESPACE} --timeout=7200s

```

**Status Progression:** `Starting` → `InProgress` → `Completed`

**✓ Validation:** The resource transitions cleanly to `status: Completed`.

---

### Step 5: Verify DC1 Cluster Health

```bash
# Verify that all DC1 nodes have completed their roll-ins and are healthy
kubectl get cassandradatacenter ${DC1_DATACENTER_NAME} -n ${NAMESPACE}

# Dynamically fetch an active seed pod from DC1 to check internal operational metrics
DC1_SEED_POD=$(kubectl get pods -n ${NAMESPACE} \
  -l "cassandra.datastax.com/datacenter=${DC1_DATACENTER_NAME},app.kubernetes.io/name=cassandra" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

# Run nodetool status using the active seed pod
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status

```

**✓ Validation:** All nodes in DC1 display status `UN` (Up/Normal).

---

### Step 6: Validate DC1 Data Restored

Extract credentials to query the Cassandra cluster data plane to confirm the target keyspace schemas have been accurately recovered.

```bash
# Retrieve internal root superuser credentials dynamically
CQL_SECRET_NAME=$(kubectl get secret -n ${NAMESPACE} | grep superuser | awk '{print $1}' | head -n 1)
CQL_PASSWD=$(kubectl get secret -n ${NAMESPACE} ${CQL_SECRET_NAME} -o jsonpath='{.data.password}' | base64 -d)
CQL_USER=$(kubectl get secret -n ${NAMESPACE} ${CQL_SECRET_NAME} -o jsonpath='{.data.username}' | base64 -d)

# Verify table properties & schemas are back on DC1
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "SELECT * FROM ${YOUR_KEYSPACE}.${YOUR_TABLE} LIMIT 5;"

```

**✓ Validation:** Data returns accurately with no unexpected empty sets or error states.

---

## PHASE 2: REBUILD & SYNC DC2 FROM DC1

### Step 7: Prepare DC2 for Rebuild

Verify that Mission Control sees DC2 as part of the wider cluster ring topology before initiating data synchronization.

```bash
# Confirm DC2 resource metrics reflect an operational, ready state
kubectl get cassandradatacenter ${DC2_DATACENTER_NAME} -n ${NAMESPACE}

# Validate cross-datacenter node visibility using the DC1 seed pod
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool describecluster

```

**✓ Validation:** Output from `describecluster` correctly lists data centers `dc1` and `dc2` within the same cluster configuration.

---

### Step 8: Create and Apply CassandraTask for DC2 Rebuild

> ⚠️ **CRITICAL:** Manual execution of `nodetool rebuild` inside container environments bypasses Mission Control's orchestration lifecycle engine. This can cause severe cluster drift and topology locks. You must use the declarative `CassandraTask` CRD.

```bash
kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: CassandraTask
metadata:
  name: rebuild-dc2-from-dc1
  namespace: ${NAMESPACE}
spec:
  datacenter:
    name: ${DC2_DATACENTER_NAME}
    namespace: ${NAMESPACE}
  jobs:
    - name: rebuild-dc2
      command: rebuild
      args:
        source_datacenter: dc1
EOF
```

**✓ Validation (apply only):** `cassandratask.control.k8ssandra.io/rebuild-dc2-from-dc1 created`. Rebuild success is validated in step 9.

---

### Step 9: Monitor and validate DC2 rebuild

Track the task until Mission Control marks every DC2 node complete.

```bash
kubectl get cassandratask rebuild-dc2-from-dc1 -n ${NAMESPACE} -w
```

In another terminal, check control-plane status:

```bash
kubectl get cassandratask rebuild-dc2-from-dc1 -n ${NAMESPACE} -o jsonpath='{.status.completionTime}{"\n"}{.status.succeeded}{"\n"}{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'

kubectl get cassandratask rebuild-dc2-from-dc1 -n ${NAMESPACE} -o go-template='{{range $pod,$s := .status.podStatuses}}{{$pod}}={{$s.status}}{{"\n"}}{{end}}'
```

Watch logs on a DC2 database pod (`app.kubernetes.io/name=cassandra`, not `cqlsh`):

```bash
DC2_SEED_POD=$(kubectl get pods -n ${NAMESPACE} \
  -l "cassandra.datastax.com/datacenter=${DC2_DATACENTER_NAME},app.kubernetes.io/name=cassandra" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

kubectl logs -f ${DC2_SEED_POD} -n ${NAMESPACE} -c server-system-logger | grep -E -i "rebuild|stream|finished"
```

**✓ Validation:** Rebuild is complete when all of the following are true:

| Check | Expected |
|-------|----------|
| `CassandraTask` condition | `Complete=True` |
| `status.completionTime` | Set (not empty) |
| `status.succeeded` | Matches DC2 node count (for example `3` on **`2-dcs`**) |
| `status.podStatuses` | Every DC2 STS pod shows `status: COMPLETED` |
| `kubectl get cassandratask` columns | `COMPLETED` time populated |
| Logger (optional) | Line contains `finished rebuild` |

If the task stays empty with no `STARTED`/`COMPLETED`, confirm `spec.datacenter.name` is **`${DC2_DATACENTER_NAME}`** (`hcd-dc2`) and `source_datacenter` is the Cassandra ring name **`dc1`**.

---

### Step 10: Verify DC2 Cluster Health

Verify that the newly rebuilt nodes are running healthy and fully recognized by the rest of the cluster topology.

```bash
# Verify both datacenters are online and healthy from a DC2 standpoint
kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status

```

**✓ Validation:** All nodes across both datacenters report status `UN`.

---

### Step 11: Validate DC2 Data Consistency

Query DC2 to verify schema synchronization and that the data volume matches the primary site.

```bash
# Validate that data can be read from DC2
kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "SELECT * FROM ${YOUR_KEYSPACE}.${YOUR_TABLE} LIMIT 5;"

# Confirm data consistency between datacenters using LOCAL_QUORUM consistency level
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "CONSISTENCY LOCAL_QUORUM; SELECT COUNT(*) FROM ${YOUR_KEYSPACE}.${YOUR_TABLE};"

kubectl exec -it ${DC2_SEED_POD} -n ${NAMESPACE} -c cassandra -- cqlsh -u ${CQL_USER} -p ${CQL_PASSWD} -e \
  "CONSISTENCY LOCAL_QUORUM; SELECT COUNT(*) FROM ${YOUR_KEYSPACE}.${YOUR_TABLE};"

```

**✓ Validation:** Row counts are consistent and query results return successfully.

---

### Step 12: Run Post-Rebuild Cleanup

> ⚠️ **CRITICAL:** After a datacenter rebuild, nodes retain temporary streaming data artifacts. You must execute a node cleanup operation across DC2 to recover disk space and remove redundant files.

```bash
kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: CassandraTask
metadata:
  name: cleanup-dc2-post-rebuild
  namespace: ${NAMESPACE}
spec:
  datacenter:
    name: ${DC2_DATACENTER_NAME}
    namespace: ${NAMESPACE}
  jobs:
    - name: cleanup-dc2
      command: cleanup
EOF

kubectl get cassandratask cleanup-dc2-post-rebuild -n ${NAMESPACE} -w
```

**✓ Validation:** Task updates status parameter matrix to `type: Complete`.

---

### Step 13: Run Post-Rebuild Targeted Sync Repair

> ⚠️ **TWCS WARNING:** When the environment uses TWCS (Time Window Compaction Strategy), do not run a blind, cluster-wide `nodetool repair -pr`. Scope repairs to a single keyspace.

> ⚠️ **No `CassandraTask` repair:** cass-operator in this lab does **not** support `command: repair` (`unknown job command: repair`). Use Mission Control UI for repairs. Supported `CassandraTask` commands here are **`rebuild`** and **`cleanup`** only.

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](02-mission-control.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **Repairs**.
3. Click **Run repair** (**Start a repair** form).
4. Set:
   - **Cluster**: `hcd`
   - **Keyspace**: `lab_restore` (or `${YOUR_KEYSPACE}`)
   - **Owner**: `admin`
   - **Segments Per Node**: `64`
   - **Repair Threads**: `1`
   - **Parallelism**: `DATACENTER_AWARE`
5. Click **Run** and monitor status in the **Repairs** list until complete.

Parallelism option:
SEQUENTIAL — Safest for a small lab or a busy cluster. Only one node anywhere is doing heavy validation work at a time. Good when you want minimal CPU/disk spike.

PARALLEL — Fastest, but can hammer every node that holds a copy of the range at once. Use when you have headroom and want the job done quickly. Reaper’s incremental repair modes only work with this setting (not relevant to your doc 08 “sync repair” step).

DATACENTER_AWARE — Typical choice for multi-DC (your 2-dcs profile). dc1 and dc2 can each have one node validating in parallel, but you don’t get “all 6 nodes in dc1 + all 6 in dc2” validating at once. That’s why doc 08 recommends it after a rebuild: you sync data across DCs without the blast radius of full PARALLEL.

**✓ Validation:** Repair row in **Repairs** shows success, then confirm data in step 14 (`nodetool describering` and CQL on both DCs).

Optional verification:

```bash
kubectl get reaper -n hcd
kubectl logs -n hcd hcd-dc1-reaper-0 -c reaper --tail=50
```

---

### Step 14: Final Validation — Both Datacenters Fully Operational

```bash
# Final check of overall cluster topology from a DC1 perspective
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool status

# Verify cross-datacenter replication status details
kubectl exec -it ${DC1_SEED_POD} -n ${NAMESPACE} -c cassandra -- nodetool describering ${YOUR_KEYSPACE}

```

**✓ Validation:**

* All nodes across both datacenters show status `UN` (Up/Normal).
* Datacenter endpoints and token rings are evenly distributed and active.

---

## Rollback Procedure

### If DC1 Restore Fails:

```bash
# 1. Delete the failed restore job resource object
kubectl delete medusarestorejob ${RESTORE_JOB_NAME} -n ${NAMESPACE}

# 2. Inspect control plane operator event logs to diagnose the issue
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=k8ssandra-operator -c k8ssandra-operator

# 3. Resolve configuration errors, update BACKUP_NAME variable, and restart from Step 3

```

### If DC2 Rebuild Fails:

```bash
# 1. Delete the active failed rebuild task
kubectl delete cassandratask rebuild-dc2-from-dc1 -n ${NAMESPACE}

# 2. Mission Control's operator automatically ceases streaming. Do not issue raw nodetool stop commands on pods.
# 3. Inspect the 'server-system-logger' container logs to identify network or streaming drop causes.

```

---

**End of Document**