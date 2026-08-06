# SUM benchmark: Pandas vs CPU OpenFHE vs GPU FIDESlib

This trusted demo sends the same plaintext values to both service Pods. Each
service creates one CKKS context/key pair, encrypts 8192-value chunks,
homomorphically sums and combines them, then decrypts once. It is separate
from the secretless `/v1/evaluate` API.

The server needs only `k3s-demo-gitops`. OpenFHE and FIDESlib stay inside their
separate CPU and GPU images.

## What code the benchmark calls

The benchmark uses JSON only as the HTTP transport:

```json
{"values":[12,7,8,9]}
```

The GitOps client sends that same JSON to both services:

```text
scripts/benchmark/sum/run.sh
  -> scripts/benchmark/sum/compare_sum.py
  -> POST /v1/demo/sum
```

CPU file flow in `k3s-demo-app`:

```text
api/app.py
  -> backends/openfhe_demo_sum.py: OpenFHEDemoSumBackend.sum_values()
  -> OpenFHE-Python: Encrypt -> EvalSum -> EvalAdd chunks -> Decrypt once
```

GPU file flow in `k3s-demo-app`:

```text
gpu/api/app.py: NativeDemoBackend.sum_many()
  -> starts /src/worker/build/he-gpu-demo
  -> gpu/worker/src/demo_main.cpp: run_large_sum()
  -> gpu/worker/src/fides_backend.cpp: FidesBackend::sum()
  -> FIDESlib: CryptoContext::AccumulateSum()
```

`gpu/api/app.py` intentionally does not import FIDESlib. It is the JSON and
process adapter. FIDESlib is a C++ library and is linked into `he-gpu-demo`;
all GPU encryption, SUM evaluation, encrypted chunk combining, and final
decryption happen in that native executable.

The plaintext JSON is only the common benchmark input. CPU and GPU both
encrypt those values before calling their HE SUM operation; neither uses a
plaintext SUM as its reported HE result.

The result separates two useful comparisons:

```text
compute_seconds
  Pandas: normal plaintext sum
  CPU/GPU: encrypted SUM + encrypted partial-sum combination

end_to_end_seconds
  Pandas: plaintext sum
  CPU/GPU: JSON transfer + context/key generation + encryption
           + encrypted computation + decryption
```

The detailed JSON also records context/key generation, encryption, encrypted
SUM, encrypted combination, decryption, native total, and HTTP round-trip
times separately. This benchmark measures HE performance, not the final
privacy boundary; the later secretless API must accept ciphertext instead.

## Build, pull, and deploy

Push `k3s-demo-app` `main`. GitLab builds `cpu-latest`; start the manual
`build-fides-evaluator-gpu` job to build `gpu-latest`. Then on the K3s server:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull origin main

HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh
```

The deploy scripts use `HE_CPU_IMAGE` and `HE_GPU_IMAGE` directly from
`config/he-lab.env`; they do not contact Docker Hub. For the work-server mirror:

```text
: "${HE_IMAGE_REPOSITORY:=hub.vtcc.vn:8989/dockerboi99/he_k8s}"
: "${HE_CPU_IMAGE_TAG:=cpu-latest}"
: "${HE_GPU_IMAGE_TAG:=gpu-latest}"
```

You can also set `HE_CPU_IMAGE` or `HE_GPU_IMAGE` to a full immutable digest in
that file when the mirror caches a moving tag.

## Benchmark client dependency

No server-side virtual environment or OpenFHE installation is required.
`run.sh` creates a Kubernetes Job using `HE_BENCH_CLIENT_IMAGE`, which defaults
to the deployed CPU image. That image contains Pandas and NumPy for the
plaintext baseline. Pull the CPU image built from the latest `k3s-demo-app`
`main` before running this benchmark.

## First 50k run

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 \
  --min-value 0 \
  --max-value 100 \
  --repetitions 1
```

## Full run

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 100000 500000 1000000 \
  --min-value 0 \
  --max-value 100 \
  --seed 42 \
  --repetitions 3 \
  --timeout 3600
```

The script does not redeploy and does not use `kubectl port-forward`. It creates
one ordinary CPU benchmark Job inside `HE_NAMESPACE`. The Job generates its
deterministic CSV, runs the Pandas baseline, and calls both ClusterIP Services:

```text
benchmark Job (no GPU requested)
  -> http://he-evaluator:8080/v1/demo/sum
  -> http://he-evaluator-gpu:8080/v1/demo/sum
```

ClusterIP works across Pods on the same or different Kubernetes nodes. This
avoids `error upgrading connection` on work-server API proxies that block
`kubectl port-forward` and `kubectl exec` streaming connections.

```text
benchmark_runs/sum/<UTC-time>/summary.csv
benchmark_runs/sum/<UTC-time>/result.json
benchmark_runs/sum/<UTC-time>/job.log
```

The generated input stays in the Job's temporary volume. `benchmark_runs/` is
ignored by Git.

## Larger-value accuracy trial

Run this only after the 0-100 test succeeds:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/sum/run.sh \
  --sizes 50000 100000 500000 1000000 \
  --min-value 0 \
  --max-value 1000000 \
  --repetitions 1 \
  --regenerate
```

This explores CKKS precision at larger totals. CKKS uses approximate real
arithmetic, so this is not a literal integer-overflow test.
