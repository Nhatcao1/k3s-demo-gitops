# HE benchmark: overall CPU and GPU guide

This is the main benchmark guide. Start here.

The server needs only `k3s-demo-gitops`, `kubectl`, and access to the container
registry. OpenFHE-Python stays in the CPU image. FIDESlib and its patched
OpenFHE stay in the separate GPU image.

## Pick the benchmark you need

| Goal | Command | What it compares |
| --- | --- | --- |
| Compare SUM performance | `scripts/benchmark/sum/run.sh` | Pandas vs CPU OpenFHE vs GPU FIDESlib |
| Test one backend and operation | `scripts/benchmark/run-he-bench.sh` | Python reference vs encrypted `/v1/evaluate` |

Use the SUM comparison first. It is the quickest way to confirm that both
services produce an accurate result and to compare their latency.

Neither command redeploys an evaluator. Both create a normal Kubernetes Job
inside `HE_NAMESPACE`; no `kubectl port-forward`, server virtual environment,
or local OpenFHE installation is required.

## What code is called

### SUM comparison

```text
scripts/benchmark/sum/run.sh
  -> Kubernetes benchmark Job
  -> scripts/benchmark/sum/compare_sum.py
     -> Pandas plaintext SUM
     -> CPU POST /v1/demo/sum
     -> GPU POST /v1/demo/sum
```

CPU service flow in `k3s-demo-app`:

```text
api/app.py
  -> backends/openfhe_demo_sum.py
  -> OpenFHE-Python: keygen -> encrypt -> EvalSum -> decrypt
```

GPU service flow in `k3s-demo-app`:

```text
gpu/api/app.py
  -> /src/worker/build/he-gpu-demo
  -> gpu/worker/src/demo_main.cpp
  -> gpu/worker/src/fides_backend.cpp
  -> FIDESlib: encrypt -> AccumulateSum -> decrypt
```

The SUM endpoint accepts plaintext only for this trusted performance demo.
Both HE services encrypt before evaluation. Pandas is the unencrypted baseline.

### Generic encrypted API benchmark

```text
scripts/benchmark/run-he-bench.sh
  -> Kubernetes benchmark Job
  -> scripts/benchmark/service_benchmark.py
  -> encrypt in trusted client
  -> POST /v1/evaluate
  -> decrypt and compare in trusted client
```

The trusted client keeps the secret key. The evaluator receives serialized
ciphertexts plus only the public/evaluation keys required by the operation.
For both `cpu` and `gpu`, the benchmark Job uses `HE_BENCH_CLIENT_IMAGE`
(normally the CPU image) as the trusted OpenFHE-Python client. Selecting `gpu`
changes the target evaluator Service; it does not request a GPU for the client
Job.

Both benchmark paths generate their own deterministic input. You do not need
to run `prepare-he-bench-data.sh` for these synthetic performance tests; that
script is reserved for later benchmarks using the real installments dataset.

Supported benchmark workloads:

| Workload | Operations | Result meaning |
| --- | --- | --- |
| `primitive` | `add`, `subtract`, `multiply` | Checks the three basic HE operations |
| `sum` | encrypted packed SUM | Checks reduction and rotation keys |
| `variance` | population variance | Checks square, SUM, mean, and CKKS accuracy per chunk |

## One-time setup

### 1. Configure the lab

Edit `config/he-lab.env` once for the target server:

```sh
: "${HE_NAMESPACE:=datalake-he}"
: "${HE_IMAGE_REPOSITORY:=hub.vtcc.vn:8989/dockerboi99/he_k8s}"
: "${HE_CPU_IMAGE_TAG:=cpu-<short-commit-sha>}"
: "${HE_GPU_IMAGE_TAG:=gpu-<short-commit-sha>}"
```

Use immutable commit tags on a caching registry mirror. Avoid `cpu-latest` and
`gpu-latest` when the mirror can keep an old manifest.

### 2. Deploy the services

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull --ff-only origin main

HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh \
  cpu-<cpu-build-short-sha>

HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh \
  gpu-<gpu-build-short-sha>
```

Check both deployments before benchmarking:

```sh
kubectl -n datalake-he get deployment,pod,service -o wide
kubectl -n datalake-he rollout status deployment/he-evaluator-cpu --timeout=10m
kubectl -n datalake-he rollout status deployment/he-evaluator-gpu --timeout=15m
```

## Recommended first run: compare SUM at 50k

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 \
  --min-value 0 \
  --max-value 100 \
  --repetitions 1
```

This single Job generates deterministic data and calls Pandas, CPU, and GPU.
Wait for the command to print the result table and output directory.

## Full SUM comparison

Run this only after the 50k test passes:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 100000 500000 1000000 \
  --min-value 0 \
  --max-value 100 \
  --seed 42 \
  --repetitions 3 \
  --timeout 3600
```

The SUM comparison currently accepts up to 1,000,000 values.

## Test individual encrypted workloads

The syntax is:

```text
./scripts/benchmark/run-he-bench.sh <cpu|gpu> \
  <primitive|sum|variance> \
  <50000|100000|500000|1000000|10000000|all>
```

Start with CPU at 50k:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh cpu primitive 50000
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh cpu sum 50000
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh cpu variance 50000
```

Then run the same checks against GPU:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh gpu primitive 50000
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh gpu sum 50000
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh gpu variance 50000
```

Run all configured sizes only after the 50k case passes:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh cpu sum all
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh gpu sum all
```

Useful one-run overrides:

```sh
REPETITIONS=3 BENCH_JOB_TIMEOUT_SECONDS=43200 \
  HE_NAMESPACE=datalake-he \
  ./scripts/benchmark/run-he-bench.sh gpu variance 500000
```

## Where results are saved

SUM comparison:

```text
benchmark_runs/sum/<UTC-time>/summary.csv
benchmark_runs/sum/<UTC-time>/result.json
benchmark_runs/sum/<UTC-time>/job.log
```

Generic encrypted benchmark:

```text
benchmark_runs/cpu_<workload>_<UTC-time>/<size>.json
benchmark_runs/cpu_<workload>_<UTC-time>/<size>.log
benchmark_runs/gpu_<workload>_<UTC-time>/<size>.json
benchmark_runs/gpu_<workload>_<UTC-time>/<size>.log
```

`benchmark_runs/` is ignored by Git.

## How to read the SUM table

| Field | Meaning |
| --- | --- |
| `backend` | `pandas`, `cpu`, or `gpu` |
| `compute_seconds` | Plain Pandas SUM, or encrypted SUM plus encrypted chunk combination |
| `end_to_end_seconds` | Full call including HE setup, encryption, evaluation, decryption, and transport |
| `abs_error`, `rel_error` | Difference from `math.fsum` reference |
| `accuracy_passed` | Whether the CKKS result is inside the configured tolerance |

Use `compute_seconds` for the closest computation comparison. Use
`end_to_end_seconds` to understand the latency a caller actually experiences.

## Quick monitoring

While a benchmark is running:

```sh
kubectl -n datalake-he get jobs,pods -w
```

Inspect a failed Job:

```sh
kubectl -n datalake-he get jobs,pods
kubectl -n datalake-he logs job/<job-name> --all-containers=true
kubectl -n datalake-he describe job/<job-name>
```

Check evaluator logs:

```sh
kubectl -n datalake-he logs deployment/he-evaluator-cpu --tail=200
kubectl -n datalake-he logs deployment/he-evaluator-gpu --tail=200
```

## Common failures

| Error | First check |
| --- | --- |
| `deployment ... not found` | Run the matching deploy script first |
| `Connection refused` | Check Deployment readiness and Service endpoints |
| `ImagePullBackOff` | Confirm the immutable tag exists in the mirror and the registry protocol is configured on every node |
| GPU Pod `Pending` | Check GPU allocation, hostname selection, toleration, and `runtimeClassName: nvidia` |
| HTTP 500 | Read evaluator logs; the benchmark Job log usually shows only the client-side failure |
| Accuracy failure | Retry 50k with values in `0..100`, then inspect CKKS parameters and timing details |
| Kubernetes `x509` error | Temporarily set `HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY=true`; leave it `false` otherwise |

For the detailed SUM trust model and timing fields, see
[`sum-benchmark.md`](sum-benchmark.md). For deployment-only commands, see
[`k3s-direct-deployment.md`](k3s-direct-deployment.md).
