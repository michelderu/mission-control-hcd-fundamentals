# Backup and restore (Mission Control + Medusa jobs)

Run a backup and restore workflow for HCD using **Mission Control UI** and verify the underlying **Medusa resources**.

**Prerequisites**

- 📂 Run from the **repository root**.
- Steps 1–3 complete (cluster and Cassandra pods Ready in namespace **`hcd`**).
- 💡 Optional: steps 4–6 if you also want to validate from CQL console, Data API, or dashboards.

## Configure object storage (embedded MinIO)

Use this section once per cluster before running backups.

### 1) Create the bucket first (`medusa-backups`)

### 🖥️ MinIO UI
You can create the bucket in the MinIO web console:

Get MinIO credentials (used for UI login or CLI):

```bash
MINIO_USER=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootPassword}' | base64 -d)
echo "$MINIO_USER"
echo "$MINIO_PASS"
```

```bash
kubectl port-forward svc/mission-control-minio-console -n mission-control 9001:9001
```

1. Open `http://localhost:9001`.
2. Log in with credentials from Secret `mission-control-minio` (`rootUser` / `rootPassword`).
3. Open **Buckets**.
4. Click **Create Bucket**.
5. Enter `medusa-backups` and create it.

### ⌨️ CLI (`mc` or `aws`)

Use a CLI installed on your workstation:

- `mc` = MinIO Client CLI (from https://dl.min.io/client/mc/release/)
- `aws` = AWS CLI (`s3api` works with S3-compatible MinIO using a custom endpoint)

Get credentials from the cluster:

```bash
MINIO_USER=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootPassword}' | base64 -d)
```

```bash
kubectl port-forward svc/mission-control-minio -n mission-control 9000:9000
```

Create bucket with `mc`:

```bash
mcli alias set local http://localhost:9000 "$MINIO_USER" "$MINIO_PASS"
mcli mb --ignore-existing local/medusa-backups
mcli ls local
```

Or create bucket with AWS CLI:

```bash
AWS_ACCESS_KEY_ID="$MINIO_USER" \
AWS_SECRET_ACCESS_KEY="$MINIO_PASS" \
aws --endpoint-url http://localhost:9000 s3api create-bucket --bucket medusa-backups || true

AWS_ACCESS_KEY_ID="$MINIO_USER" \
AWS_SECRET_ACCESS_KEY="$MINIO_PASS" \
aws --endpoint-url http://localhost:9000 s3api list-buckets
```

> 💡 Keep this port-forward running while using `mc`/`aws` against local endpoint `localhost:9000`:
>
> ```bash
> kubectl port-forward svc/mission-control-minio -n mission-control 9000:9000
> ```

### 2) Create Medusa credentials Secret (required for UI and CLI path)

This Secret is required regardless of how backups are triggered:

- UI flow in Mission Control
- CLI flow with Medusa resources

```bash
MINIO_USER=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_PASS=$(kubectl get secret mission-control-minio -n mission-control -o jsonpath='{.data.rootPassword}' | base64 -d)
```

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: medusa-bucket-key
  namespace: hcd
type: Opaque
stringData:
  credentials: |-
    [default]
    aws_access_key_id = ${MINIO_USER}
    aws_secret_access_key = ${MINIO_PASS}
EOF
```

### 3) Configure backup storage

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080`.
2. Go to **Settings** → **Backup Configuration**.
3. Click **Create a new configuration**.
4. Fill **Create Backup Configuration** with lab values:
   - **Configuration Name**: `minio-lab` (or any name you prefer)
   - **Storage Provider**: `S3-compatible` (or `S3` in older UI labels)
   - **Bucket Name**: `medusa-backups`
   - **Host**: `mission-control-minio.mission-control.svc.cluster.local`
   - **Port**: `9000`
   - **Secure**: OFF
   - **Verify SSL**: OFF
   - **Concurrent Transfers**: keep default (`1`)
   - **Credentials**: use MinIO `rootUser` / `rootPassword` from Secret `mission-control-minio`
5. Click **Create Backup Configuration**, then ensure your HCD cluster uses this backup configuration.

### ⌨️ CLI

Patch the existing `MissionControlCluster` with `manifests/hcd/medusa/enable-medusa.yaml`:

```bash
kubectl patch missioncontrolcluster hcd -n hcd \
  --type merge \
  --patch-file manifests/hcd/medusa/enable-medusa.yaml
```

> ⚠️ **Important:** the Secret referenced by `storageSecretRef.name` must exist in namespace `hcd` before cluster reconciliation; otherwise nodes can wait for the missing secret.

## What this step does

This guide demonstrates:

1. Create sample data.
2. Start a backup from Mission Control UI.
3. Track the `MedusaBackupJob` / `MedusaBackup` resources.
4. Simulate data loss.
5. Start a restore from Mission Control UI.
6. Track restore progress and validate recovered rows.

> ⚠️ **Lab scope:** this walkthrough validates backup/restore behavior on a lab cluster. In production, define backup schedules/retention and run regular restore drills across your full topology.

## 1) Create sample data

Use **`PROFILE=2-dcs`** so both datacenters exist. Replication uses Cassandra DC names (`dc1`, `dc2`), not Mission Control names (`hcd-dc1`, `hcd-dc2`).

### ⌨️ CLI

```bash
DB_USER=$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.username}' | base64 -d)
DB_PASS=$(kubectl get secret hcd-superuser -n hcd -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -it hcd-hcd-dc1-rack1-sts-0 -n hcd -c cassandra -- cqlsh \
  -u "$DB_USER" -p "$DB_PASS" -e "
CREATE KEYSPACE IF NOT EXISTS lab_restore
WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 3, 'dc2': 3}
AND durable_writes = true;
CREATE TABLE IF NOT EXISTS lab_restore.users (
  id int PRIMARY KEY,
  name text
);
INSERT INTO lab_restore.users (id, name) VALUES (1, 'alice');
INSERT INTO lab_restore.users (id, name) VALUES (2, 'bob');
SELECT * FROM lab_restore.users;
"
```

Run a **full repair** on `lab_restore` through Mission Control so replicas exist in both datacenters before backup. Do not run `nodetool repair` directly on pods.

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](02-mission-control.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`** → **Repairs**.
3. Click **Run repair**.
4. Select keyspace **`lab_restore`**.
5. Run repair for **`hcd-dc1`**, wait until complete, then run repair for **`hcd-dc2`**.

### ⌨️ CLI

Use a `CassandraTask` per datacenter (Cassandra DC names `dc1` / `dc2`):

```bash
kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: CassandraTask
metadata:
  name: repair-lab-restore-dc1
  namespace: hcd
spec:
  datacenter:
    name: dc1
    namespace: hcd
  jobs:
    - name: repair-lab-restore
      command: repair
      args:
        keyspace_name: lab_restore
EOF

kubectl apply -f - <<EOF
apiVersion: control.k8ssandra.io/v1alpha1
kind: CassandraTask
metadata:
  name: repair-lab-restore-dc2
  namespace: hcd
spec:
  datacenter:
    name: dc2
    namespace: hcd
  jobs:
    - name: repair-lab-restore
      command: repair
      args:
        keyspace_name: lab_restore
EOF

kubectl get cassandratask repair-lab-restore-dc1 repair-lab-restore-dc2 -n hcd -w
```

Repair is complete when both tasks show `status.conditions` with `type: Complete` and `status: "True"`.

> 💡 On **`minimal`** or **`3-racks`**, use `'dc1': 1` only (no `dc2` in replication) and skip the DC2 repair task.

## 2) Start a backup in Mission Control

### 🖥️ Mission Control UI

```bash
kubectl port-forward svc/mission-control-ui -n mission-control 8080:8080
```

1. Open `https://localhost:8080` ([Mission Control login](02-mission-control.md#access-the-ui)).
2. **Home** → project **`hcd`** → cluster **`hcd`**.
3. Open the **Backups** view.
4. Click **Create backup** (or **Run backup now** if a policy already exists).
5. Select datacenter `hcd-dc1`, then submit.
6. Note the backup name/ID shown in the UI (used for restore in step 5).

### ⌨️ CLI

Create a `MedusaBackupJob` for datacenter `hcd-dc1`. The job name becomes the backup name used in restore (step 5).

```bash
BACKUP_JOB_NAME="backup-lab-$(date -u +%Y-%m-%dT%H-%M-%S | tr '[:upper:]' '[:lower:]')z"

kubectl apply -f - <<EOF
apiVersion: medusa.k8ssandra.io/v1alpha1
kind: MedusaBackupJob
metadata:
  name: ${BACKUP_JOB_NAME}
  namespace: hcd
spec:
  backupType: full
  cassandraDatacenter: hcd-dc1
EOF

kubectl get medusabackupjob ${BACKUP_JOB_NAME} -n hcd -w
```

> 💡 Use `backupType: differential` only when a recent full backup already exists for this datacenter.

## 3) Track backup status (Medusa resources)

### ⌨️ CLI

List Medusa backup resources:

```bash
kubectl get medusabackupjob -n hcd
kubectl get medusabackup -n hcd
```

Inspect a backup job status (replace with your backup job name):

```bash
kubectl get medusabackupjob -n hcd BACKUP_JOB_NAME -o yaml
```

Inspect resulting backup object (replace with your backup name):

```bash
kubectl get medusabackup -n hcd BACKUP_NAME -o yaml
```

Backup is complete when `finishTime` is set on `MedusaBackupJob`, `MedusaBackup.status.status` is `SUCCESS`, and the UI marks it successful.

## 4) Simulate data loss

### ⌨️ CLI

```bash
kubectl exec -it hcd-hcd-dc1-rack1-sts-0 -n hcd -c cassandra -- cqlsh \
  -u "$DB_USER" -p "$DB_PASS" -e "
TRUNCATE lab_restore.users;
SELECT * FROM lab_restore.users;
"
```

## 5) Start restore in Mission Control

### 🖥️ Mission Control UI

1. In the same cluster, open **Backups**.
2. Select the backup from step 2.
3. Click **Restore**.
4. Choose the target datacenter (`hcd-dc1`) and submit.
5. Wait for restore status to become successful.

## 6) Track restore status and validate

### ⌨️ CLI

Track restore resources:

```bash
kubectl get medusarestorejob -n hcd
kubectl get medusarestore -n hcd
```

Inspect a restore job (replace with your restore job name):

```bash
kubectl get medusarestorejob -n hcd RESTORE_JOB_NAME -o yaml
```

Validate data:

```bash
kubectl exec -it hcd-hcd-dc1-rack1-sts-0 -n hcd -c cassandra -- cqlsh \
  -u "$DB_USER" -p "$DB_PASS" -e "SELECT * FROM lab_restore.users;"
```

Expected result: rows for `alice` and `bob` are visible again.

## Cleanup (optional)

### ⌨️ CLI

```bash
kubectl exec -it hcd-hcd-dc1-rack1-sts-0 -n hcd -c cassandra -- cqlsh \
  -u "$DB_USER" -p "$DB_PASS" -e "
DROP TABLE IF EXISTS lab_restore.users;
DROP KEYSPACE IF EXISTS lab_restore;
"
```

## 🔧 Troubleshooting

| Symptom | Check |
|---------|--------|
| No backup option in UI | Verify MC version/features and that cluster is Ready |
| Backup fails quickly | Check Medusa credentials and object storage connectivity |
| No Medusa backup resource appears | `kubectl get events -n hcd --sort-by=.lastTimestamp` for operator errors |
| Restore completes but rows missing | Confirm selected backup ID and target datacenter |
