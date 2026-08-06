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

## Install benchmark dependencies once

```sh
python3 -m venv .venv-he-sum
source .venv-he-sum/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r scripts/benchmark/sum/requirements.txt
```

This installs only Pandas and NumPy in `.venv-he-sum`, not OpenFHE.
After installation, either keep the environment active or run `deactivate`;
`run.sh` calls `.venv-he-sum/bin/python` directly.

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

The script does not redeploy. It opens temporary port-forwards, generates or
reuses `data/sum-benchmark/values.csv`, calls the running services, saves the
results, and closes the port-forwards.

Do not start separate `kubectl port-forward` commands before `run.sh`. The
script owns ports `HE_CPU_LOCAL_PORT` and `HE_GPU_LOCAL_PORT`, waits for both
Deployments and `/readyz` endpoints, and closes both tunnels on exit. If a
tunnel or remote Pod fails, it now prints the corresponding log immediately:

```text
benchmark_runs/sum/<UTC-time>/cpu-port-forward.log
benchmark_runs/sum/<UTC-time>/gpu-port-forward.log
```

Use different values in `config/he-lab.env` only when port 18080 or 18081 is
already occupied.

```text
benchmark_runs/sum/<UTC-time>/summary.csv
benchmark_runs/sum/<UTC-time>/details.json
```

Both `data/` and `benchmark_runs/` are ignored by Git.

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
