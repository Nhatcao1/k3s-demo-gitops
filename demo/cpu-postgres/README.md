# CPU OpenFHE salary session demo with PostgreSQL

This isolated demo proves that separate CPU Jobs can continue one encrypted
session through PostgreSQL:

```text
fake salaries -> encrypt -> encrypted SUM -> encrypted SUM * encrypted KPI
              -> trusted verification
```

The supplied example uses salaries `[1200, 1800, 2400, 3000]` and KPI `0.8`.
The sum and multiply Jobs receive no plaintext salary input, plaintext KPI,
wrapping key, or raw secret key. They load only the serialized CKKS context,
ciphertexts, and operation-specific evaluation keys from PostgreSQL.

## Trust boundary

PostgreSQL stores the encrypted salary vector, encrypted KPI, encrypted sum,
encrypted final result, CKKS context, evaluation keys, hashes, and session
metadata. The OpenFHE secret key is serialized and AES-256-GCM wrapped before
it enters PostgreSQL. The wrapping key is held in a separate Kubernetes Secret
and is mounted only into the trusted initialize and verify Jobs.

Kubernetes Secrets are not automatically confidential from cluster
administrators and may not be encrypted at rest on every K3s installation.
This is a small functional demo, not a claim that a cluster administrator
cannot recover the test inputs. Production input encryption should happen on
a trusted external client and the wrapping key should come from a KMS/HSM.

## Repositories and branch

The demo uses the existing GitLab repositories and the same branch name in
both:

```sh
git clone --branch feat/cpu-postgres-demo \
  git@gitlab.com:nhatcao99uetwork/k3s-demo-app.git

git clone --branch feat/cpu-postgres-demo \
  git@gitlab.com:nhatcao99uetwork/k3s-demo-gitops.git
```

The PostgreSQL session package is included in the existing CPU image. The same
CPU API now exposes `multiply` for ciphertext-by-ciphertext and
`multiply_plain` for ciphertext-by-public-plaintext multiplication. All
server-side runtime files remain under this directory in `k3s-demo-gitops`.

After reviewing the two additive directories, publish the branches to the
same existing GitLab remotes:

```sh
cd k3s-demo-app
git add .gitlab-ci.yml Dockerfile requirements.txt api backends common \
  openfhe_cpu client/cpu_service_demo.py tests demo/cpu-postgres
git commit -m "Add CPU multiply modes and PostgreSQL HE demo"
git push -u origin feat/cpu-postgres-demo

cd ../k3s-demo-gitops
git add demo/cpu-postgres
git commit -m "Add CPU HE PostgreSQL demo manifests"
git push -u origin feat/cpu-postgres-demo
```

These commands do not merge or push to `main`. The CPU build job is explicitly
enabled for `feat/cpu-postgres-demo`, so pushing that application branch builds
both `cpu-$CI_COMMIT_SHA` and `cpu-latest` when the configured Docker Hub
credentials are available. The default-branch build rule remains unchanged.

Optional application-side validation before building the image:

```sh
python3 -m venv /tmp/cpu-postgres-demo-venv
/tmp/cpu-postgres-demo-venv/bin/pip install \
  'cryptography>=43,<48' 'psycopg[binary]>=3.2,<4'
PYTHONPATH=demo/cpu-postgres \
  /tmp/cpu-postgres-demo-venv/bin/python -m unittest discover \
  -s demo/cpu-postgres/tests -v
python3 -m unittest discover -s tests -v
```

## 1. Build and push the combined CPU image

Run from the `k3s-demo-app` repository on a Docker-authenticated build host.
This builds the evaluator, both multiply modes, and PostgreSQL session CLI into
the existing `cpu-latest` image:

```sh
docker login docker.io

docker buildx build \
  --platform linux/amd64 \
  --file Dockerfile \
  --tag docker.io/dockerboi99/he_k8s:cpu-latest \
  --push \
  .
```

The Kubernetes Jobs use `imagePullPolicy: Always` and pull
`docker.io/dockerboi99/he_k8s:cpu-latest`. Existing CPU evaluator Pods must be
restarted after publishing the moving tag:

```sh
kubectl -n he-dev rollout restart deployment/he-evaluator-cpu
kubectl -n he-dev rollout status deployment/he-evaluator-cpu --timeout=10m
```

The PostgreSQL demo Jobs do not require that Deployment; each Job runs the
same CPU image directly.

The CPU HTTP request forms are:

```json
{"operation":"multiply","context":"...","ciphertext_a":"...","ciphertext_b":"...","evaluation_keys":"..."}
```

```json
{"operation":"multiply_plain","context":"...","ciphertext_a":"...","plaintext_b":0.8}
```

`multiply` keeps both inputs encrypted and requires relinearization keys.
`multiply_plain` accepts a public scalar or numeric vector and does not require
relinearization keys. The salary/KPI workflow below deliberately uses
ciphertext-by-ciphertext multiplication so the KPI remains encrypted.

## 2. Create the namespace and Kubernetes Secrets

Run from any host with `kubectl` access to the K3s cluster. The following are
fake demonstration values. Shell variables use demo-specific names so they do
not overwrite standard environment variables.

```sh
kubectl create namespace he-dev --dry-run=client -o yaml \
  | kubectl apply -f -

demo_db_password=$(openssl rand -hex 24)
demo_wrap_key=$(openssl rand -base64 32 | tr -d '\n')

kubectl -n he-dev create secret generic cpu-postgres-demo-db \
  --from-literal=POSTGRES_DB=he_demo \
  --from-literal=POSTGRES_USER=he_demo \
  --from-literal=POSTGRES_PASSWORD="$demo_db_password" \
  --from-literal=PGDATABASE=he_demo \
  --from-literal=PGUSER=he_demo \
  --from-literal=PGPASSWORD="$demo_db_password" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n he-dev create secret generic cpu-postgres-demo-input \
  --from-literal=DEMO_SALARIES_JSON='[1200,1800,2400,3000]' \
  --from-literal=DEMO_KPI='0.8' \
  --from-literal=DEMO_KEY_WRAP_KEY="$demo_wrap_key" \
  --dry-run=client -o yaml | kubectl apply -f -

unset demo_db_password demo_wrap_key
```

Do not apply `k8s/secrets.example.yaml`; it documents the required keys but
contains deliberately invalid placeholders.

## 3. Run the complete demo

On the K3s server, from the `k3s-demo-gitops` repository:

```sh
cd demo/cpu-postgres
./scripts/run-demo.sh
```

The script deploys PostgreSQL, applies the schema, and runs initialize, sum,
multiply, verify, and inspect Jobs in sequence. Successful stage logs contain:

```text
"status":"INITIALIZED"
"status":"SUMMED"
"status":"MULTIPLIED"
"status":"PASS"
"status":"VERIFIED"
```

Verification compares the decrypted first result slot with
`sum(salaries) * KPI` inside the trusted verifier. It logs only PASS/FAIL and
the approximation error, not the decrypted salary aggregate.

## Run every stage explicitly

These commands are equivalent to the runner and are useful while debugging.

Deploy PostgreSQL and wait for readiness:

```sh
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/schema-configmap.yaml
kubectl apply -f k8s/postgres.yaml
kubectl -n he-dev rollout status statefulset/cpu-postgres-demo --timeout=10m
```

Create the schema:

```sh
demo_job=$(kubectl create -f k8s/schema-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=5m
kubectl -n he-dev logs "job/$demo_job"
```

Generate the context and keys, encrypt salaries/KPI, wrap the secret key, and
create the PostgreSQL session:

```sh
demo_job=$(kubectl create -f k8s/initialize-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=15m
kubectl -n he-dev logs "job/$demo_job"
```

Calculate and store the encrypted salary sum:

```sh
demo_job=$(kubectl create -f k8s/sum-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=15m
kubectl -n he-dev logs "job/$demo_job"
```

Reload the encrypted sum and multiply it by the encrypted KPI:

```sh
demo_job=$(kubectl create -f k8s/multiply-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=15m
kubectl -n he-dev logs "job/$demo_job"
```

Decrypt and verify only the final aggregate in the trusted Job:

```sh
demo_job=$(kubectl create -f k8s/verify-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=15m
kubectl -n he-dev logs "job/$demo_job"
```

Inspect artifact names, sizes, hashes, and status without reading payloads:

```sh
demo_job=$(kubectl create -f k8s/inspect-job.yaml \
  -o jsonpath='{.metadata.name}')
kubectl -n he-dev wait --for=condition=complete "job/$demo_job" --timeout=5m
kubectl -n he-dev logs "job/$demo_job"
```

## Operational checks

Show all demo resources and accumulated Job logs:

```sh
./scripts/status.sh
```

Inspect PostgreSQL metadata without selecting ciphertext/key payloads:

```sh
kubectl -n he-dev exec statefulset/cpu-postgres-demo -- sh -ec \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT session_id,status,valid_count,created_at,updated_at FROM he_demo_sessions"'

kubectl -n he-dev exec statefulset/cpu-postgres-demo -- sh -ec \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT artifact_name,octet_length(payload) AS bytes,sha256 FROM he_demo_artifacts ORDER BY artifact_name"'
```

To use a new session ID before another complete run, patch the existing
ConfigMap. The runner preserves an existing demo ConfigMap:

```sh
kubectl -n he-dev patch configmap cpu-postgres-demo-config \
  --type merge -p '{"data":{"DEMO_SESSION_ID":"salary-demo-002"}}'
```

To change the fake KPI from `0.8` to `0.9` while preserving the existing
wrapping key:

```sh
kubectl -n he-dev patch secret cpu-postgres-demo-input \
  --type merge -p '{"stringData":{"DEMO_KPI":"0.9"}}'
```

Use a new session ID after changing an input. Do not replace the wrapping key
until every session created with the old key has been verified or discarded.

## Cleanup

Delete only completed demo Jobs while preserving PostgreSQL and session data:

```sh
./scripts/cleanup.sh --jobs
```

Delete all demo resources, Secrets, and the PostgreSQL PVC permanently:

```sh
./scripts/cleanup.sh --all
```

The `--all` command irreversibly removes every stored demo session and its
wrapped secret key.
