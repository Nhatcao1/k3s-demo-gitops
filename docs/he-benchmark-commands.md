# HE benchmark: Python vs CPU vs GPU

This is the main benchmark guide. Start here.

The recommended runner sends the same deterministic values to:

```text
Python baseline
CPU OpenFHE
GPU FIDESlib
```

It compares all currently exposed demo operations in one Kubernetes Job:

```text
add  subtract  multiply  square  sum  mean  variance
```

No `kubectl port-forward`, server virtual environment, or local OpenFHE
installation is required. OpenFHE-Python stays in the CPU image. FIDESlib and
its patched OpenFHE stay in the separate GPU image.

## What the runner calls

```text
scripts/benchmark/compare/run.sh
  -> Kubernetes comparison Job
  -> scripts/benchmark/compare/compare_operations.py
     -> Python baseline
     -> CPU Service
     -> GPU Service
```

For `add`, `subtract`, `multiply`, `square`, `mean`, and `variance`:

```text
POST /v1/demo/evaluate
```

The API accepts at most 4096 values per request, so the runner splits a larger
dataset into identical chunks for CPU and GPU and adds their timings.

For SUM:

```text
POST /v1/demo/sum
```

SUM uses the dedicated large-vector path and produces one global encrypted SUM
for up to 1,000,000 values.

These are trusted benchmark endpoints: plaintext enters each service, but CPU
and GPU both perform key generation, encryption, HE evaluation, and decryption
inside their own backend. Python is the unencrypted reference.

## One-time setup

### 1. Configure the target server

Edit `config/he-lab.env`:

```sh
: "${HE_NAMESPACE:=datalake-he}"
: "${HE_IMAGE_REPOSITORY:=hub.vtcc.vn:8989/dockerboi99/he_k8s}"
: "${HE_CPU_IMAGE_TAG:=cpu-<short-commit-sha>}"
: "${HE_GPU_IMAGE_TAG:=gpu-<short-commit-sha>}"
```

Use immutable commit tags on a caching registry mirror. Avoid moving
`cpu-latest` and `gpu-latest` tags when the mirror may retain an old manifest.

### 2. Deploy CPU and GPU

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull --ff-only origin main

HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh \
  cpu-<cpu-build-short-sha>

HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh \
  gpu-<gpu-build-short-sha>
```

Check both services:

```sh
kubectl -n datalake-he get deployment,pod,service -o wide
kubectl -n datalake-he rollout status deployment/he-evaluator-cpu --timeout=10m
kubectl -n datalake-he rollout status deployment/he-evaluator-gpu --timeout=15m
```

## First run: all operations at 1,000 values

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations all \
  --sizes 1000 \
  --min-value 0 \
  --max-value 100 \
  --repetitions 1
```

This produces one table containing Python, CPU, and GPU rows for every
operation. Start here before using larger sizes.

## Compare selected operations

For the newly added GPU functions:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations square mean variance \
  --sizes 4096 \
  --min-value 0 \
  --max-value 100 \
  --repetitions 1
```

For the primitive functions:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations add subtract multiply \
  --sizes 4096 \
  --repetitions 1
```

For one operation at several sizes:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations variance \
  --sizes 1000 4096 50000 \
  --repetitions 1 \
  --timeout 3600
```

## Full comparison

Run this only after the 1,000-value test passes. It can take a long time
because every non-SUM block creates a real HE context and keypair.

```sh
HE_NAMESPACE=datalake-he BENCH_JOB_TIMEOUT_SECONDS=43200 \
  ./scripts/benchmark/compare/run.sh \
  --operations all \
  --sizes 4096 50000 100000 \
  --min-value 0 \
  --max-value 100 \
  --seed 42 \
  --repetitions 3 \
  --timeout 3600
```

The runner accepts up to 1,000,000 values. Use larger sizes one operation at a
time rather than starting a very large `all` run.

## Important result scopes

| Operation | Scope reported by the runner |
| --- | --- |
| `add`, `subtract`, `multiply`, `square` | All element-wise output values across all chunks |
| `sum` | One global SUM across the full dataset |
| `mean`, `variance` | One scalar result per 4096-value chunk |

`mean` and `variance` are currently per-chunk for datasets larger than 4096.
The runner does not pretend that plaintext combination of chunk results is a
global HE reduction. A future large-vector backend endpoint must perform the
encrypted cross-chunk combination before those rows can be labelled global.

## Dedicated large SUM comparison

The existing SUM runner remains useful because it has a more detailed timing
breakdown and writes a Pandas baseline:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 100000 500000 1000000 \
  --min-value 0 \
  --max-value 100 \
  --seed 42 \
  --repetitions 3 \
  --timeout 3600
```

See [`sum-benchmark.md`](sum-benchmark.md) for its detailed trust model and
timing fields.

## Optional encrypted API contract benchmark

`run-he-bench.sh` is still available when you need to test the serialized
ciphertext `/v1/evaluate` contract. It compares one selected backend against a
Python reference; it is not the main CPU-vs-GPU comparison runner.

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh cpu variance 50000
HE_NAMESPACE=datalake-he ./scripts/benchmark/run-he-bench.sh gpu variance 50000
```

The trusted benchmark Job keeps the secret key. The evaluator receives only
ciphertexts and the required public/evaluation keys.

## Results

The unified comparison saves:

```text
benchmark_runs/compare/<UTC-time>/summary.csv
benchmark_runs/compare/<UTC-time>/result.json
benchmark_runs/compare/<UTC-time>/job.log
```

`benchmark_runs/` is ignored by Git.

The terminal table contains:

| Field | Meaning |
| --- | --- |
| `operation` | HE function under test |
| `backend` | `python`, `cpu`, or `gpu` |
| `values` | Total input values processed |
| `chunks` | Number of demo API requests, except global SUM |
| `service_s` | Python compute time, or time reported inside the HE service |
| `end_to_end_s` | Full client-observed HTTP time |
| `abs_error` | Maximum difference from the Python reference |
| `pass` | Whether absolute or relative error is inside tolerance |

For SUM, `result.json` also records `he_compute_seconds` from encrypted SUM and
encrypted partial-result combination. Other demo operations currently expose
only total `evaluation_seconds`.

## Monitoring

```sh
kubectl -n datalake-he get jobs,pods -w
```

Inspect a failed comparison:

```sh
kubectl -n datalake-he get jobs,pods
kubectl -n datalake-he logs job/<job-name> --all-containers=true
kubectl -n datalake-he describe job/<job-name>

kubectl -n datalake-he logs deployment/he-evaluator-cpu --tail=200
kubectl -n datalake-he logs deployment/he-evaluator-gpu --tail=200
```

## Common failures

| Error | First check |
| --- | --- |
| `deployment ... not found` | Run the matching deploy script first |
| Missing demo operation | Deploy CPU and GPU images built from the new app code |
| `Connection refused` | Check Deployment readiness and Service endpoints |
| `ImagePullBackOff` | Confirm the immutable tag exists and registry protocol is configured on every node |
| GPU Pod `Pending` | Check GPU allocation, hostname, toleration, and `runtimeClassName: nvidia` |
| HTTP 500 | Read evaluator logs; the Job log generally shows only the client failure |
| Accuracy failure | Retry 1,000 values in range `0..100`, then inspect CKKS parameters |
| Kubernetes `x509` error | Temporarily set `HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY=true` |

For deployment-only commands, see
[`k3s-direct-deployment.md`](k3s-direct-deployment.md).
