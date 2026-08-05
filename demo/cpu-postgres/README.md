# CPU HE + PostgreSQL demo

Purpose: encrypt salary CSV and KPI, store artifacts in PostgreSQL, calculate encrypted SUM, then encrypted SUM × KPI.

## 1. Configure

Edit namespace, scheme, session, KPI, salary range and images:

```sh
vi demo.env
```

Generate 100 salaries using `demo.env`:

```sh
./scripts/generate-salaries.sh
```

Generate a different count:

```sh
./scripts/generate-salaries.sh 500
```

Review or edit the generated CSV:

```sh
head salaries.csv
vi salaries.csv
```

Use CKKS:

```text
DEMO_SCHEME=ckks
DEMO_SESSION_ID=salary-ckks-001
```

Use BGV with the same CPU image:

```text
DEMO_SCHEME=bgv
DEMO_SESSION_ID=salary-bgv-001
```

## 2. Setup K3s and PostgreSQL

Create namespace, Secrets, configuration, PostgreSQL and schema:

```sh
./scripts/setup.sh
```

Prepare a small helper for the individual Jobs in this terminal:

```sh
set -a
. ./demo.env
set +a

renderer=../../scripts/render-he-yaml.py

run_job() {
  manifest=$1
  job=$(python3 "$renderer" "k8s/$manifest" | kubectl create -f - -o name)
  kubectl -n "$DEMO_NAMESPACE" wait --for=condition=complete "$job" --timeout=15m
  kubectl -n "$DEMO_NAMESPACE" logs "$job"
}
```

## 3. Create context, keys and encrypted inputs

```sh
run_job initialize-job.yaml
./scripts/status.sh
```

## 4. Calculate encrypted SUM

```sh
run_job sum-job.yaml
./scripts/status.sh
```

## 5. Multiply encrypted SUM by encrypted KPI

```sh
run_job multiply-job.yaml
./scripts/status.sh
```

## 6. Decrypt and verify the final result

```sh
run_job verify-job.yaml
./scripts/status.sh
```

## 7. Inspect PostgreSQL

Show session progress:

```sh
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,scheme,status,valid_count,kpi_scale,updated_at FROM he_demo_sessions ORDER BY created_at;"'
```

Show completed operations:

```sh
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,operation,outcome,completed_at FROM he_demo_operations ORDER BY operation_id;"'
```

Show artifact sizes:

```sh
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,artifact_name,octet_length(payload) AS bytes FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

Run the metadata inspector:

```sh
run_job inspect-job.yaml
```

Show the wrapped secret key stored in PostgreSQL:

```sh
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,encode(payload, '\''base64'\'') FROM he_demo_artifacts WHERE artifact_name='\''wrapped_secret_key'\'';"'
```

Lab only: unwrap and print the raw secret key:

```sh
./scripts/show-secret-key.sh
```

## 8. Cleanup

Delete Jobs:

```sh
./scripts/cleanup.sh
```

Delete PostgreSQL and all demo data:

```sh
./scripts/cleanup.sh --all
```

Flow: [`FLOW.mmd`](FLOW.mmd).
