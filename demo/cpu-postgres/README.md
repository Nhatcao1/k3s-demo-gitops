# CPU HE + PostgreSQL demo

Purpose: encrypt salary CSV and KPI, store artifacts in PostgreSQL, calculate encrypted SUM, then encrypted SUM × KPI.

## 1. Configure and generate input

Edit `demo.env` for namespace, scheme, session, images, salary range and TLS:

```sh
vi demo.env
```

CKKS values belong in `demo.env`:

```text
DEMO_SCHEME=ckks
DEMO_SESSION_ID=salary-ckks-001
```

BGV values belong in the same `demo.env` file and use the same CPU image:

```text
DEMO_SCHEME=bgv
DEMO_SESSION_ID=salary-bgv-001
```

For a temporary K3s certificate problem, set this in `demo.env`:

```text
DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY=true
```

Generate 100 salaries and KPI `0.8`:

```sh
./scripts/generate-salaries.sh 100 0.8
```

Generated private input files:

```text
salaries.csv  # salary values
input.env     # DEMO_KPI
```

Show or edit the original input:

```sh
head salaries.csv
cat input.env
vi salaries.csv
```

## 2. Setup K3s and PostgreSQL

```sh
./scripts/setup.sh
```

`setup.sh` creates concrete Job files under `rendered/` from `demo.env`.

Load namespace and TLS values for the commands below:

```sh
set -a
. ./demo.env
set +a
```

## 3. Create context, keys and encrypted inputs

```sh
job=$(kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  create -f rendered/initialize-job.yaml -o name)
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" wait --for=condition=complete "$job" --timeout=15m
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" logs "$job"
```

Show PostgreSQL status, operations, ciphertexts, context and key previews:

```sh
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,scheme,status,valid_count,updated_at FROM he_demo_sessions ORDER BY created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 4. Calculate encrypted SUM

```sh
job=$(kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  create -f rendered/sum-job.yaml -o name)
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" wait --for=condition=complete "$job" --timeout=15m
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" logs "$job"
```

Check PostgreSQL again; `sum_ciphertext` should now exist:

```sh
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,status FROM he_demo_sessions ORDER BY created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 5. Multiply encrypted SUM by encrypted KPI

```sh
job=$(kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  create -f rendered/multiply-job.yaml -o name)
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" wait --for=condition=complete "$job" --timeout=15m
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" logs "$job"
```

Check PostgreSQL again; `kpi_result_ciphertext` should now exist:

```sh
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,status FROM he_demo_sessions ORDER BY created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 6. Decrypt and verify

```sh
job=$(kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  create -f rendered/verify-job.yaml -o name)
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" wait --for=condition=complete "$job" --timeout=15m
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" logs "$job"
```

Show final PostgreSQL progress:

```sh
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,scheme,status,valid_count,updated_at FROM he_demo_sessions ORDER BY created_at; SELECT session_id,operation,outcome,completed_at FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 7. Keys and status

Show Kubernetes and database status:

```sh
./scripts/status.sh
```

Show the wrapped secret key stored in PostgreSQL:

```sh
kubectl --insecure-skip-tls-verify="$DEMO_KUBECTL_INSECURE_SKIP_TLS_VERIFY" \
  -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,encode(payload,'\''base64'\'') FROM he_demo_artifacts WHERE artifact_name='\''wrapped_secret_key'\'';"'
```

Lab only: unwrap and print the raw secret key:

```sh
./scripts/show-secret-key.sh
```

## 8. Cleanup

```sh
./scripts/cleanup.sh
./scripts/cleanup.sh --all
```

Flow: [`FLOW.mmd`](FLOW.mmd).
