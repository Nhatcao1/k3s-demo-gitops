# Deployed-service benchmark commands

These benchmarks call the already-deployed evaluator Service. For quick CPU
development, port-forward the Service and run the Python client directly. A
Kubernetes Job remains available for cluster-side and GPU testing.

```text
benchmark client Job
  -> http://he-evaluator:8080/v1/evaluate
  -> he-evaluator-cpu Deployment
```

Neither method redeploys the evaluator. Only
`scripts/benchmark/deploy-cpu-service.sh` and `deploy-gpu-service.sh` change the
evaluator Deployments.

## Benchmark files

All benchmark and direct-deployment scripts live together:

```text
scripts/benchmark/
├── deploy-cpu-service.sh
├── deploy-gpu-service.sh
├── run-he-bench.sh
├── service_benchmark.py
├── primitives.py
├── payment_diff_sum_mean.py
├── prepare-he-bench-data.sh
└── prepare_full_installments_columns.py

k8s/
├── cpu-evaluator.yaml
├── gpu-evaluator.yaml
└── benchmark-job.yaml
```

`service_benchmark.py` is the active implementation. The small
`primitives.py` and `payment_diff_sum_mean.py` entry points use the same
service benchmark implementation.

Shared non-secret K3s settings are in `config/he-lab.env`. Change that one file
before pushing if the namespace, Docker Hub images, or Service names differ on
another server.

The YAML files are normal tracked templates. `${HE_...}` values come from
`config/he-lab.env`; `${BENCH_...}` values come from the benchmark command.
The scripts render them with `scripts/render-he-yaml.py` and pipe the result to
`kubectl`. Edit resource requests, limits, probes, and volume mounts directly
in the YAML files rather than inside shell code.

For example, changing these values in `config/he-lab.env` updates every deploy
and benchmark command:

```sh
: "${HE_NAMESPACE:=he-dev}"
: "${HE_CPU_IMAGE_TAG:=cpu-latest}"
: "${HE_GPU_IMAGE_TAG:=gpu-latest}"
: "${HE_CPU_SERVICE:=he-evaluator}"
: "${HE_GPU_SERVICE:=he-evaluator-gpu}"
```

An exported shell value still overrides the tracked default for one run:

```sh
HE_NAMESPACE=he-trial \
  ./scripts/benchmark/deploy-cpu-service.sh
```

## 1. Deploy or refresh the CPU service

Wait for the `k3s-demo-app` GitLab pipeline to publish the CPU `cpu-latest` image,
then run:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull --ff-only

./scripts/benchmark/deploy-cpu-service.sh
```

Check the service:

```sh
kubectl -n he-dev get deployment,pods,service -o wide
kubectl -n he-dev get service he-evaluator
```

## 2. Recommended: run Python directly against the existing CPU service

Install OpenFHE-Python once in a server-side virtual environment:

```sh
python3 -m venv .venv-he-bench
. .venv-he-bench/bin/activate
python -m pip install --upgrade pip
python -m pip install openfhe
```

In terminal 1, expose the existing ClusterIP Service only to the local server:

```sh
kubectl -n he-dev port-forward service/he-evaluator 18080:8080
```

In terminal 2, activate the same environment and run the client directly:

```sh
. .venv-he-bench/bin/activate

python scripts/benchmark/service_benchmark.py \
  --url http://127.0.0.1:18080/v1/evaluate \
  --workload primitive \
  --value-count 50000 \
  --batch-size 8192 \
  --repetitions 1 \
  --timeout 300

python scripts/benchmark/service_benchmark.py \
  --url http://127.0.0.1:18080/v1/evaluate \
  --workload sum \
  --value-count 50000

python scripts/benchmark/service_benchmark.py \
  --url http://127.0.0.1:18080/v1/evaluate \
  --workload variance \
  --value-count 50000
```

`primitive` runs `add`, `subtract`, and `multiply`. This path creates no new
Kubernetes Job or ConfigMap. Stop the port-forward with `Ctrl-C` when finished.

## 3. Optional: create and run a benchmark Job

Primitive runs test `add`, `subtract`, and `multiply`:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 50000
```

SUM runs test encrypted packed `sum`:

```sh
./scripts/benchmark/run-he-bench.sh cpu sum 50000
```

Population variance runs `E[x²] - E[x]²` and compares each encrypted CKKS
chunk with the matching Python variance:

```sh
./scripts/benchmark/run-he-bench.sh cpu variance 50000
```

The command creates the benchmark code ConfigMap, creates a Kubernetes Job,
waits for completion, and copies the Job log to a JSON file under
`benchmark_runs/`.

## GPU: deploy and run the same benchmark

First run the manual `build-fides-evaluator-gpu` GitLab job. After the
`dockerboi99/he_k8s:gpu-latest` image is pushed and the K3s NVIDIA device plugin is
working, confirm that `hht-k8s-staging-22` is schedulable and has the
`dedicated=T4:NoSchedule` toleration declared in `k8s/gpu-evaluator.yaml`:

```sh
kubectl get nodes \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

./scripts/benchmark/deploy-gpu-service.sh
kubectl -n he-dev rollout status deployment/he-evaluator-gpu --timeout=15m

./scripts/benchmark/run-he-bench.sh gpu primitive 50000
./scripts/benchmark/run-he-bench.sh gpu sum 50000
./scripts/benchmark/run-he-bench.sh gpu variance 50000
```

The benchmark command does not create the evaluator. If it reports that
`he-evaluator-gpu` is not found, run `deploy-gpu-service.sh` first. If the GPU
Deployment stays Pending, inspect it with:

```sh
kubectl -n he-dev get pods -l app=he-evaluator-gpu
kubectl -n he-dev describe pods -l app=he-evaluator-gpu
```

The benchmark Job is still the trusted standard OpenFHE-Python client. It sends
the public key to FIDESlib because the GPU backend needs it to load evaluation
keys, but it never sends the secret key. CPU and GPU remain separate images.

## 4. Run one larger Job size

Allowed sizes are `50000`, `100000`, `500000`, `1000000`, and `10000000`:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 500000
./scripts/benchmark/run-he-bench.sh cpu sum 500000
./scripts/benchmark/run-he-bench.sh cpu variance 500000
```

## 5. Run the complete Job matrix

Start this only after both 50k Jobs pass:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive all
./scripts/benchmark/run-he-bench.sh cpu sum all
./scripts/benchmark/run-he-bench.sh cpu variance all
```

## 6. Job repetitions and timeouts

```sh
REPETITIONS=5 \
  ./scripts/benchmark/run-he-bench.sh cpu primitive 500000

REPETITIONS=5 BENCH_JOB_TIMEOUT_SECONDS=43200 \
  ./scripts/benchmark/run-he-bench.sh cpu sum 10000000
```

Optional overrides:

```sh
export BATCH_SIZE=8192
export REQUEST_TIMEOUT_SECONDS=300
export HE_NAMESPACE=he-dev
export HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY=false
export HE_SERVICE_URL=http://he-evaluator:8080/v1/evaluate
export BENCH_IMAGE=docker.io/dockerboi99/he_k8s:cpu-latest
```

These shell overrides take priority over `config/he-lab.env` for one run.
Set the TLS option to `true` only when `kubectl` reports an `x509` error from a
temporary lab certificate.

## Measurements

For every operation, the result JSON records:

- matching plain-Python operation time;
- trusted-client encryption time;
- ciphertext serialization time;
- HTTP/service round-trip time;
- evaluator-reported evaluation time;
- trusted-client decryption time;
- total encrypted end-to-end time and slowdown versus Python;
- throughput, chunk count, CKKS error, and PASS/FAIL.

The secret key stays only in the trusted benchmark client—either the Job or the
direct local Python process—and is never included in the HTTP request. Inputs
are bounded deterministic values generated one CKKS chunk at a time, allowing
the 10m test without loading 10m Python values into memory simultaneously. The
evaluator is stateless and does not save keys, input ciphertexts, or result
ciphertexts.

For `variance`, a 50k-or-larger run measures and validates every CKKS chunk;
it does not claim one global variance across all chunks. A global variance
needs encrypted cross-chunk moment aggregation and remains separate work.

## Ciphertext chaining and lifetime

The existing API can be called repeatedly without redeploying it. A client can
encrypt `12`, `7`, `8`, and `9` under one CKKS context/keypair, then chain:

```text
ct12 + ct7  -> ct19
ct19 + ct8  -> ct27
ct27 + ct9  -> ct36
```

The client must keep the same crypto context and secret key in memory and keep
each returned ciphertext for the next request. The service only evaluates one
request and returns one serialized ciphertext; it does not currently assign
ciphertext IDs or provide storage.

`service_benchmark.py` uses temporary files only for OpenFHE serialization.
Those files are automatically removed, and its keys/ciphertexts disappear when
the Python process exits. Long-lived ciphertexts would need explicit client-side
serialization. A secret key must go into protected secret storage, never Git or
the GitOps data directory.

## Results and troubleshooting

```sh
find benchmark_runs -maxdepth 3 -type f -print | sort
cat benchmark_runs/service_primitive_*/50000.json

kubectl -n he-dev get jobs,pods
kubectl -n he-dev logs job/<job-name>
kubectl -n he-dev describe job/<job-name>
```

GPU remains experimental until the FIDESlib image and remote ciphertext path
pass on the target NVIDIA server.
