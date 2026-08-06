# CPU HE + PostgreSQL demo

Purpose: encrypt salary CSV and KPI, store the HE artifacts in PostgreSQL, calculate encrypted SUM, then encrypted SUM × encrypted KPI.

## 1. Pull the demo branch

In an existing GitOps clone:

```sh
git fetch origin feat/cpu-postgres-demo
git switch feat/cpu-postgres-demo
git pull --ff-only origin feat/cpu-postgres-demo
cd demo/cpu-postgres
```

For a new clone:

```sh
git clone --branch feat/cpu-postgres-demo --single-branch \
  git@gitlab.com:nhatcao99uetwork/k3s-demo-gitops.git
cd k3s-demo-gitops/demo/cpu-postgres
```

The demo pulls the public image `docker.io/dockerboi99/he_k8s:cpu-postgres-demo`.

Optional: verify the K3s node can pull it before setup:

```sh
sudo k3s crictl pull docker.io/dockerboi99/he_k8s:cpu-postgres-demo
```

No GitLab branch switch is required for normal builds: a push to `feat/cpu-postgres-demo` triggers the app pipeline and publishes this tag. If the Docker Hub CI variables are protected, protect this feature branch once before retrying the pipeline.

## 2. Configure and generate input

Edit namespace, scheme, session, images, salary range and TLS in this file:

```sh
vi demo.env
```

Find the node name for InternalIP `100.106.33.74`:

```sh
kubectl get nodes -o wide
```

Pin PostgreSQL and every demo Job to that node in `demo.env`:

```text
DEMO_NODE_NAME=node2
```

Use CKKS in `demo.env`:

```text
DEMO_SCHEME=ckks
DEMO_SESSION_ID=salary-ckks-001
```

Use BGV in the same `demo.env`; it uses the same CPU image:

```text
DEMO_SCHEME=bgv
DEMO_SESSION_ID=salary-bgv-001
```

Generate 100 salaries and KPI `0.8`:

```sh
./scripts/generate-salaries.sh 100 0.8
```

Generated input files:

```text
salaries.csv  # salary values
input.env     # DEMO_KPI
```

Show or edit the plaintext inputs:

```sh
head salaries.csv
cat input.env
vi salaries.csv
```

## 3. Setup K3s and PostgreSQL

```sh
./scripts/setup.sh
```

`setup.sh` deploys PostgreSQL and writes concrete Job YAML to `rendered/`.

The commands below use namespace `he-dev`; change it in `demo.env`, rerun setup, and replace `he-dev` below if needed. The insecure TLS flag is shown for a lab K3s certificate issue.

## 4. Create context, keys and encrypted inputs

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/initialize-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  wait --for=condition=complete job \
  -l he.demo/stage=initialize --timeout=15m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -l he.demo/stage=initialize --all-containers=true --prefix=true
```

Show expected plaintext, operations, ciphertexts, context and wrapped key:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.scheme,s.status,s.valid_count,r.expected_amount,r.decrypted_amount,r.absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

`expected_amount` is a demo-only plaintext reference calculated with exact Python integer and decimal arithmetic.

`he_demo_results` contains one expected/decrypted comparison row per session.

## 5. Calculate encrypted SUM

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/sum-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  wait --for=condition=complete job \
  -l he.demo/stage=sum --timeout=15m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -l he.demo/stage=sum --all-containers=true --prefix=true
```

Show the new `sum_ciphertext` and session progress:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.status,r.expected_amount,r.decrypted_amount,r.absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 6. Multiply encrypted SUM by encrypted KPI

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/multiply-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  wait --for=condition=complete job \
  -l he.demo/stage=multiply --timeout=15m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -l he.demo/stage=multiply --all-containers=true --prefix=true
```

Show the new `kpi_result_ciphertext` and session progress:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.status,r.expected_amount,r.decrypted_amount,r.absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

## 7. Decrypt and verify

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/verify-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  wait --for=condition=complete job \
  -l he.demo/stage=verify --timeout=15m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -l he.demo/stage=verify --all-containers=true --prefix=true
```

Compare `expected_amount`, `decrypted_amount` and `absolute_error`:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.scheme,s.status,s.valid_count,r.expected_amount,r.decrypted_amount,r.absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome,completed_at FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

BGV should have zero error when the configured plaintext modulus is large enough; CKKS has a small approximation error.

## 8. Keys and status

```sh
./scripts/status.sh
```

Show the wrapped secret key stored in PostgreSQL:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT session_id,encode(payload,'\''base64'\'') FROM he_demo_artifacts WHERE artifact_name='\''wrapped_secret_key'\'';"'
```

Lab only: unwrap and print the raw secret key:

```sh
./scripts/show-secret-key.sh
```

## 9. Cleanup

Delete demo Jobs before starting a new session; change `DEMO_SESSION_ID` and rerun setup first:

```sh
./scripts/cleanup.sh
```

Reset the same session by deleting the full demo, including PostgreSQL storage, then run setup again:

```sh
./scripts/cleanup.sh --all
```

Flow: [`FLOW.mmd`](FLOW.mmd).
