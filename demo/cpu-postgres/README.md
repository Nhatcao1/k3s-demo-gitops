# CPU HE + PostgreSQL demo

## Configure

Create a private salary CSV:

```sh
cd demo/cpu-postgres
cp salaries.example.csv salaries.csv
vi salaries.csv
```

Each salary must be an integer from `10000000` to `200000000`; maximum 8192 rows.

Select the namespace, scheme, session, KPI and images:

```sh
vi demo.env
```

Use one published image for both schemes:

```text
DEMO_HE_IMAGE=docker.io/dockerboi99/he_k8s:cpu-latest
DEMO_SCHEME=ckks
DEMO_SESSION_ID=salary-ckks-001
DEMO_KPI=0.8
```

For BGV, change only the scheme and session:

```text
DEMO_SCHEME=bgv
DEMO_SESSION_ID=salary-bgv-001
```

## Deploy and run

Deploy PostgreSQL, encrypt the CSV and KPI, SUM, multiply, verify and inspect:

```sh
./scripts/run-demo.sh
```

Show Kubernetes and database progress:

```sh
./scripts/status.sh
```

Show sessions:

```sh
. ./demo.env
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,scheme,status,valid_count,kpi_scale,updated_at FROM he_demo_sessions ORDER BY created_at;"'
```

Show completed operations:

```sh
. ./demo.env
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,operation,outcome,completed_at FROM he_demo_operations ORDER BY operation_id;"'
```

Show stored ciphertext/context/key artifact sizes without printing payloads:

```sh
. ./demo.env
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,artifact_name,octet_length(payload) AS bytes FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

Show the wrapped secret key stored by PostgreSQL:

```sh
. ./demo.env
kubectl -n "$DEMO_NAMESPACE" exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,encode(payload, '\''base64'\'') AS wrapped_secret_key FROM he_demo_artifacts WHERE artifact_name='\''wrapped_secret_key'\'';"'
```

Lab only: unwrap and print the raw secret key:

```sh
./scripts/show-secret-key.sh
```

## Cleanup

Delete Jobs only:

```sh
./scripts/cleanup.sh
```

Delete the complete demo including PostgreSQL data:

```sh
./scripts/cleanup.sh --all
```

Flow diagram: [`FLOW.mmd`](FLOW.mmd).
