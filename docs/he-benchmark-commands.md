# Primitive and SUM benchmark commands

All benchmark Python and shell scripts belong in `scripts/benchmark/`:

```text
scripts/benchmark/
├── prepare-he-bench-data.sh
├── prepare_full_installments_columns.py
├── primitives.py
├── payment_diff_sum_mean.py
└── run-he-bench.sh
```

Commands below are run from the GitOps repository. Script, input, and result
defaults are resolved relative to the repository, so the same checkout works
on a laptop or server.

## One-time setup

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
chmod +x scripts/benchmark/*.sh

mkdir -p data/home_credit
cp /path/to/installments_payments.csv \
  data/home_credit/installments_payments.csv
```

OpenFHE can use the system Python or a relative virtual environment:

```sh
export PYTHON_BIN=python3
# Or:
# export PYTHON_BIN=./.venv-openfhe/bin/python
```

Optional path overrides:

```sh
export DATA_DIR=./data
export OUTPUT_DIR=./benchmark_runs/manual-run
```

## Prepare benchmark data

This recreates `data/prepared/installments_columns/`:

```sh
./scripts/benchmark/prepare-he-bench-data.sh
```

## Small CPU run first

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 50000
./scripts/benchmark/run-he-bench.sh cpu sum 50000
```

Allowed sizes are `50000`, `100000`, `500000`, `1000000`, and `10000000`.

## Run the full CPU matrix

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive all
./scripts/benchmark/run-he-bench.sh cpu sum all
```

Run more repetitions only after the one-repetition runs pass:

```sh
REPETITIONS=5 \
  ./scripts/benchmark/run-he-bench.sh cpu primitive 500000

REPETITIONS=5 \
  ./scripts/benchmark/run-he-bench.sh cpu sum 500000
```

Unless `OUTPUT_DIR` is set, results are written beneath:

```text
benchmark_runs/cpu_primitive_<UTC-run-id>/
benchmark_runs/cpu_sum_<UTC-run-id>/
```

Inspect the newest results with:

```sh
find benchmark_runs -maxdepth 3 -type f -print | sort
```

## Current implementation gate

The copied Python files still import the old `code.openfhe_direct` session.
They must be adjusted to call the new `/v1/evaluate` service before these
commands are considered service benchmarks. GPU execution remains disabled
until FIDESlib remote ciphertext transport is implemented.

Kubernetes Deployment and Service commands are in
[`docs/k3s-direct-deployment.md`](k3s-direct-deployment.md). Argo CD is not
used during this phase.
