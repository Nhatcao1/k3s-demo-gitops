# CPU HE + PostgreSQL demo

Purpose: encrypt salary and per-row KPI values, store the HE artifacts in PostgreSQL, calculate encrypted salary SUM and encrypted `SUM(salary[i] × KPI[i])`.

Main calculation:

```text
weighted[i] = salary[i] × KPI[i]
final_total = SUM(weighted[i])
```

The standalone salary SUM is only a reference/checkpoint. Its
`sum_ciphertext` is not used to calculate `final_total`.

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
Build commit `8d51c2826f8eb0a247d687a79d9305c75573fa56` publishes three equivalent
tags after its GitLab pipeline succeeds:

```text
cpu-postgres-demo
cpu-8d51c282
cpu-8d51c2826f8eb0a247d687a79d9305c75573fa56
```

Use `cpu-postgres-demo` for convenience. Use either immutable SHA tag when
you must prove exactly which application code ran.

Optional: verify the K3s node can pull it before setup:

```sh
sudo k3s crictl pull docker.io/dockerboi99/he_k8s:cpu-postgres-demo
```

No GitLab branch switch is required for normal builds: a push to `feat/cpu-postgres-demo` triggers the app pipeline and publishes this tag. If the Docker Hub CI variables are protected, protect this feature branch once before retrying the pipeline.

### Functions included in the same CPU image

The Postgres workflow Jobs still execute only the salary SUM and weighted KPI
calculation described below. The same image also contains the general CPU HE
service with:

```text
add, subtract, multiply, multiply_plain, square, sum, mean, variance
```

`variance` is population variance `E[x²] - E[x]²`. The Postgres workflow and
the general HTTP demo are separate entry points; adding these functions does
not change the stored salary/KPI workflow.

To deploy the HTTP evaluator from the repository root:

```sh
cd ../..
./scripts/benchmark/deploy-cpu-service.sh cpu-8d51c282
kubectl -n he-dev rollout status deployment/he-evaluator-cpu --timeout=10m
```

In terminal 1:

```sh
kubectl -n he-dev port-forward service/he-evaluator 18080:8080
```

In terminal 2, verify the image and run the new demos:

```sh
curl -sS http://127.0.0.1:18080/v1/capabilities | python3 -m json.tool

curl -sS -X POST http://127.0.0.1:18080/v1/demo/evaluate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"square","values_a":[1,2,3,4]}'

curl -sS -X POST http://127.0.0.1:18080/v1/demo/evaluate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"mean","values_a":[1,2,3,4]}'

curl -sS -X POST http://127.0.0.1:18080/v1/demo/evaluate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"variance","values_a":[1,2,3,4]}'
```

Expected `values` are `[1,4,9,16]`, `[2.5]`, and approximately `[1.25]`.
This endpoint accepts plaintext deliberately for a quick functional check; it
is not the secretless production boundary. `POST /v1/evaluate` remains the
ciphertext API.

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
DEMO_NODE_NAME=node3
```

HE Jobs use this node-local PostgreSQL forward from `demo.env`:

```text
DEMO_POSTGRES_FORWARD_HOST=127.0.0.1
DEMO_POSTGRES_FORWARD_PORT=15432
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

Generate 100 rows. Every salary gets a random KPI from
`0.8, 0.9, 1.0, 1.1, 1.2`:

The KPI choices are set by `DEMO_KPI_VALUES` in `demo.env`.

```sh
./scripts/generate-salaries.sh 100
```

Generated input file:

```text
salaries.csv  # salary,kpi per row
```

Show or edit the plaintext inputs:

```sh
head salaries.csv
vi salaries.csv
```

CSV format:

```csv
salary,kpi
10000000,0.8
12500000,1.1
```

## 3. Setup K3s and PostgreSQL

```sh
./scripts/setup.sh
```

`setup.sh` deploys PostgreSQL and writes concrete Job YAML to `rendered/`.

The commands below use namespace `he-dev`; change it in `demo.env`, rerun setup, and replace `he-dev` below if needed. The insecure TLS flag is shown for a lab K3s certificate issue.

## 4. Start the PostgreSQL port-forward

Run this on `node3` and keep the terminal open for all HE Jobs:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  port-forward --address 127.0.0.1 \
  statefulset/cpu-postgres-demo 15432:5432
```

Expected:

```text
Forwarding from 127.0.0.1:15432 -> 5432
```

The HE Jobs use the `node3` host network and connect to this forward at `127.0.0.1:15432`.

Run the remaining commands in a second terminal on `node3`.

## 5. Create context, keys and encrypted inputs

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  delete job -l he.demo/stage=initialize --ignore-not-found

kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/initialize-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -f -l he.demo/stage=initialize --all-containers=true \
  --prefix=true --pod-running-timeout=5m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  get job -l he.demo/stage=initialize
```

Show the expected salary SUM, expected weighted total, ciphertexts, context and
wrapped key:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.scheme,s.status,s.valid_count,r.expected_sum AS expected_salary_sum,r.expected_kpi_amount AS expected_weighted_total FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome FROM he_demo_operations ORDER BY operation_id; SELECT session_id,artifact_name,CASE artifact_name WHEN '\''salary_ciphertext'\'' THEN '\''encrypted salary vector'\'' WHEN '\''kpi_ciphertext'\'' THEN '\''encrypted per-row KPI vector'\'' WHEN '\''wrapped_secret_key'\'' THEN '\''AES-GCM wrapped lab key; not raw key'\'' ELSE '\''HE metadata or evaluation key'\'' END AS description,octet_length(payload) AS bytes,left(encode(payload,'\''hex'\''),64) AS encrypted_preview FROM he_demo_artifacts ORDER BY session_id,artifact_name;"'
```

`expected_sum` and `expected_kpi_amount = SUM(salary[i] × KPI[i])` are demo-only
plaintext references calculated with exact Python integer and decimal
arithmetic.

`he_demo_results` contains one row per session with separate SUM and KPI
expected/decrypted/error columns.

## 6. Reference only: calculate the raw encrypted salary SUM

This checkpoint verifies `SUM(salary[i])`. It does not multiply KPI values and
its output is not an input to the main calculation in step 7.

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  delete job -l he.demo/stage=sum --ignore-not-found

kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/sum-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -f -l he.demo/stage=sum --all-containers=true \
  --prefix=true --pod-running-timeout=5m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  get job -l he.demo/stage=sum
```

`sum_ciphertext` is opaque encrypted bytes. PostgreSQL cannot subtract it from
`expected_sum`. Run the separate trusted verifier: it copies only that
ciphertext, the context and wrapped lab key into private temporary files,
decrypts one scalar, and writes the observed value/error back to PostgreSQL.
The SUM evaluator above remains secretless.

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  delete job -l he.demo/stage=verify-sum --ignore-not-found

kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/verify-sum-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -f -l he.demo/stage=verify-sum --all-containers=true \
  --prefix=true --pod-running-timeout=5m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  get job -l he.demo/stage=verify-sum
```

Calculate the signed SUM difference in PostgreSQL:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.status,r.expected_sum,r.decrypted_sum,(r.decrypted_sum-r.expected_sum) AS sum_difference,r.sum_absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT artifact_name,CASE artifact_name WHEN '\''sum_ciphertext'\'' THEN '\''encrypted SUM; copied only by trusted verify-sum Job'\'' ELSE '\''supporting HE artifact'\'' END AS description,octet_length(payload) AS bytes FROM he_demo_artifacts WHERE artifact_name='\''sum_ciphertext'\'' ORDER BY session_id;"'
```

## 7. Main calculation: multiply each encrypted row, then SUM

Inside this Job, HE operations run in this order:

```text
weighted_ciphertext = salary_ciphertext × kpi_ciphertext
kpi_result_ciphertext = SUM(weighted_ciphertext)
```

The Job reads `salary_ciphertext` and `kpi_ciphertext`; it does not read
`sum_ciphertext` from step 6.

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  delete job -l he.demo/stage=multiply --ignore-not-found

kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/multiply-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -f -l he.demo/stage=multiply --all-containers=true \
  --prefix=true --pod-running-timeout=5m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  get job -l he.demo/stage=multiply
```

Show the new `kpi_result_ciphertext`; the observed KPI amount is still NULL
until the trusted KPI verifier decrypts it:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.status,r.expected_kpi_amount AS expected_weighted_total,r.decrypted_kpi_amount AS decrypted_weighted_total FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,artifact_name,'\''encrypted SUM of salary[i] × KPI[i]'\'' AS description,octet_length(payload) AS bytes FROM he_demo_artifacts WHERE artifact_name='\''kpi_result_ciphertext'\'' ORDER BY session_id;"'
```

## 8. Decrypt and compare the final weighted total

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  delete job -l he.demo/stage=verify-kpi --ignore-not-found

kubectl -n he-dev --insecure-skip-tls-verify=true \
  create -f rendered/verify-job.yaml

kubectl -n he-dev --insecure-skip-tls-verify=true \
  logs -f -l he.demo/stage=verify-kpi --all-containers=true \
  --prefix=true --pod-running-timeout=5m

kubectl -n he-dev --insecure-skip-tls-verify=true \
  get job -l he.demo/stage=verify-kpi
```

Compare `SUM(salary[i] × KPI[i])` calculated by Python with the decrypted HE
result:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT s.session_id,s.scheme,s.status,r.expected_kpi_amount AS expected_weighted_total,r.decrypted_kpi_amount AS decrypted_weighted_total,(r.decrypted_kpi_amount-r.expected_kpi_amount) AS signed_difference,r.kpi_absolute_error AS absolute_error FROM he_demo_sessions AS s JOIN he_demo_results AS r USING (session_id) ORDER BY s.created_at; SELECT session_id,operation,outcome,completed_at FROM he_demo_operations ORDER BY operation_id;"'
```

BGV should have zero error when the configured plaintext modulus is large enough; CKKS has a small approximation error.

## 9. Keys and status

Every command writes a row to `he_demo_job_runs` before doing HE work. A normal
exception is updated to `FAILED` with its error detail. If a pod is killed
without handling the error, its last row remains `RUNNING` instead of
disappearing.

```sh
./scripts/status.sh
```

Show only failed or interrupted attempts:

```sh
kubectl -n he-dev --insecure-skip-tls-verify=true \
  exec statefulset/cpu-postgres-demo -- sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT run_id,session_id,command,outcome,detail,started_at,finished_at FROM he_demo_job_runs WHERE outcome IN ('\''FAILED'\'','\''RUNNING'\'') ORDER BY run_id;"'
```

A verification mismatch still exits non-zero, but its decrypted value,
expected value and absolute error remain in `he_demo_results`; the failure
detail remains in `he_demo_job_runs`.

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

## 10. Cleanup

Stop the port-forward with `Ctrl-C` after the HE Jobs finish.

Delete demo Jobs before starting a new session; change `DEMO_SESSION_ID` and rerun setup first:

```sh
./scripts/cleanup.sh
```

Reset the same session by deleting the full demo, including PostgreSQL storage, then run setup again:

```sh
./scripts/cleanup.sh --all
```

Flow: [`FLOW.mmd`](FLOW.mmd).
