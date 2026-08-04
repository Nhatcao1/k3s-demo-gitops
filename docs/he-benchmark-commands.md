# Deployed-service benchmark commands

These benchmarks run as Kubernetes Jobs inside `he-dev` and call only the
deployed evaluator Service:

```text
benchmark client Job
  -> http://he-evaluator:8080/v1/evaluate
  -> he-evaluator-cpu Deployment
```

No Pod IP, port-forward, Argo CD, or OpenFHE installation on the server shell
is required.

## Benchmark files

All benchmark and direct-deployment scripts live together:

```text
scripts/benchmark/
├── deploy-cpu-service.sh
├── run-he-bench.sh
├── service_benchmark.py
├── primitives.py
├── payment_diff_sum_mean.py
├── prepare-he-bench-data.sh
└── prepare_full_installments_columns.py
```

`service_benchmark.py` is the active implementation. The small
`primitives.py` and `payment_diff_sum_mean.py` entry points use the same
service benchmark implementation.

## 1. Deploy or refresh the CPU service

Wait for the `k3s-demo-app` GitLab pipeline to publish the CPU `latest` image,
then run:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull --ff-only

./scripts/create-registry-secrets.sh       # only needed initially/token change
./scripts/benchmark/deploy-cpu-service.sh
```

Check the service:

```sh
kubectl -n he-dev get deployment,pods,service -o wide
kubectl -n he-dev get service he-evaluator
```

## 2. Create and run a small benchmark Job

Primitive runs test `add`, `subtract`, and `multiply`:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 50000
```

SUM runs test encrypted packed `sum`:

```sh
./scripts/benchmark/run-he-bench.sh cpu sum 50000
```

The command creates the benchmark code ConfigMap, creates a Kubernetes Job,
waits for completion, and copies the Job log to a JSON file under
`benchmark_runs/`.

## GPU: deploy and run the same benchmark

First run the manual `build-fides-evaluator-gpu` GitLab job. After the
`dockerboi99/he_k8s:latest` image is pushed and the K3s NVIDIA device plugin is
working:

```sh
./scripts/benchmark/deploy-gpu-service.sh latest
./scripts/benchmark/run-he-bench.sh gpu primitive 50000
./scripts/benchmark/run-he-bench.sh gpu sum 50000
```

The benchmark Job is still the trusted standard OpenFHE-Python client. It sends
the public key to FIDESlib because the GPU backend needs it to load evaluation
keys, but it never sends the secret key. CPU and GPU remain separate images.

## 3. Run one larger size

Allowed sizes are `50000`, `100000`, `500000`, `1000000`, and `10000000`:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 500000
./scripts/benchmark/run-he-bench.sh cpu sum 500000
```

## 4. Run the complete matrix

Start this only after both 50k Jobs pass:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive all
./scripts/benchmark/run-he-bench.sh cpu sum all
```

## 5. Repetitions and timeouts

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
export HE_SERVICE_URL=http://he-evaluator:8080/v1/evaluate
export BENCH_IMAGE=registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-evaluator-cpu:latest
```

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

The secret key stays only in the benchmark client Job and is never included in
the HTTP request. Inputs are bounded deterministic values generated one CKKS
chunk at a time, allowing the 10m test without loading 10m Python values into
memory simultaneously.

## Results and troubleshooting

```sh
find benchmark_runs -maxdepth 3 -type f -print | sort
cat benchmark_runs/service_primitive_*/50000.json

kubectl -n he-dev get jobs,pods
kubectl -n he-dev logs job/<job-name>
kubectl -n he-dev describe job/<job-name>
```

GPU remains disabled until FIDESlib remote ciphertext transport is complete.
