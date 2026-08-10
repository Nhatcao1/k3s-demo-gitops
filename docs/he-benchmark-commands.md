# HE demo benchmark commands

The benchmark compares identical reusable data with:

```text
Python baseline -> CPU OpenFHE demo API -> GPU FIDESlib demo API
```

It runs inside Kubernetes and calls the ClusterIP Services. No port-forward or
server OpenFHE installation is required.

## 1. Deploy CPU and GPU

Set the image repository and immutable tags in `config/he-lab.env`, then run:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh
```

CPU and GPU use their own encryptors inside their existing demo Service:

```text
CPU: OpenFHE-Python encrypt -> calculate -> decrypt
GPU: FIDESlib C++ encrypt -> calculate -> decrypt
```

There is no extra shared encryptor Pod. The response reports encryption time
separately, while `calculation_seconds` remains the main operation-performance
measurement.

## 2. Prepare reusable data once

This creates a persistent volume and streams CSV rows into it without keeping
the complete dataset in RAM:

```sh
HE_NAMESPACE=datalake-he \
./scripts/benchmark/compare/prepare-data.sh \
  --count 1000000 \
  --data-profiles all \
  --seed 42
```

The default PVC is `he-comparison-data` with size `10Gi`. Change
`HE_COMPARE_DATA_PVC` or `HE_COMPARE_DATA_STORAGE` in `config/he-lab.env` if
needed. The cluster must have a default StorageClass.

Running the same preparation command again verifies and reuses matching files.
Use `--force` only when you intentionally want to regenerate them. If a later
run needs two million values, prepare again with `--count 2000000`; every
profile keeps stable deterministic prefixes for A and B.

The standalone generator code is
`scripts/benchmark/compare/generate_data.py`. It can also run outside K3s:

```sh
python3 scripts/benchmark/compare/generate_data.py \
  --output-dir data/he-comparison \
  --count 100000 \
  --data-profiles positive_decimal_3 negative_decimal_3 \
  --seed 42
```

Local files are useful for inspection. The Kubernetes benchmark reads the
files prepared on its PVC.

## 3. Small iterative run

Start with one operation and two sizes:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations sum \
  --sizes 5000 10000 \
  --data-profiles positive_decimal_3 \
  --repetitions 1 \
  --timeout 3600
```

The Job works in this order:

```text
load 5k from CSV -> Python/CPU/GPU -> emit result -> release arrays
load 10k from CSV -> Python/CPU/GPU -> emit result -> release arrays
```

It does not hold the largest data for every profile in memory. Each completed
profile/size is written immediately to the Kubernetes Job log. If a later case
fails, `run.sh` still extracts the completed cases into the result files.

## 4. Add sizes, profiles, and operations

Several sizes and profiles still run in one Kubernetes Job:

```sh
HE_NAMESPACE=datalake-he BENCH_JOB_TIMEOUT_SECONDS=43200 \
./scripts/benchmark/compare/run.sh \
  --operations sum \
  --sizes 5000 10000 50000 100000 500000 1000000 \
  --data-profiles \
    positive_integer negative_integer \
    positive_decimal_1 negative_decimal_1 \
    positive_decimal_2 negative_decimal_2 \
    positive_decimal_3 negative_decimal_3 \
    positive_decimal_6 negative_decimal_6 \
  --repetitions 3 \
  --timeout 3600
```

`--data-profiles all` is the shorter equivalent. Test the other operations on
small sizes before expanding them:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations add subtract multiply square sum mean variance \
  --sizes 5000 10000 \
  --data-profiles positive_decimal_3 \
  --repetitions 1 \
  --timeout 3600
```

All profile values remain within `[-40000, 40000]`.

## 5. Deterministic limit stress run

The stress profiles are separate from the existing random profiles. Their
integer part follows the exact bounded sequence; decimal profiles add
deterministic seeded random digits after the decimal point:

```text
sequential_positive_integer:  1, 2, ... 40000, 1, 2, ...
sequential_negative_integer: -1,-2, ...-40000,-1,-2, ...
sequential_*_decimal_1:        upward integer part + 1 random decimal digit
sequential_*_decimal_2:        upward integer part + 2 random decimal digits
sequential_*_decimal_3:        upward integer part + 3 random decimal digits
sequential_*_decimal_6:        upward integer part + 6 random decimal digits
```

A and B have independent fractional streams. They are repeatable for the same
seed. The `40000` endpoint uses a zero fractional part to remain within the
`[-40000, 40000]` input bound.

Prepare one ten-million-row prefix on the same existing PVC. This does not
delete or replace any random-profile CSV:

```sh
HE_NAMESPACE=datalake-he \
./scripts/benchmark/compare/prepare-data.sh \
  --count 10000000 \
  --data-profiles stress
```

Then increase ADD from five million to ten million rows in one Job:

```sh
HE_NAMESPACE=datalake-he BENCH_JOB_TIMEOUT_SECONDS=43200 \
./scripts/benchmark/compare/run.sh \
  --operations add \
  --sizes 5000000 6000000 7000000 8000000 9000000 10000000 \
  --data-profiles stress \
  --repetitions 1 \
  --timeout 3600
```

For a shorter decimal-only trial, replace `stress` with selected names such as
`sequential_positive_decimal_3 sequential_negative_decimal_3`.

Before every load or backend attempt, the runner writes a recoverable marker.
Normal Python/HTTP exceptions become explicit failure records. If Kubernetes
kills the process outright, such as `OOMKilled`, `run.sh` combines the last
attempt marker with Pod termination details. Completed sizes remain in
`summary.csv`; the first failed limit is written to `failures.csv` and
`result.json`.

## Demo API paths

The Job uses:

```text
POST /v1/demo/evaluate  # add/subtract/multiply/square/mean/variance
POST /v1/demo/sum       # large-vector SUM
```

Plaintext enters these trusted demo endpoints. Each Service performs context
and key creation, encryption, HE calculation, and decryption with its own HE
library. The production-style secretless ciphertext endpoint remains
`/v1/evaluate`.

Non-SUM operations are split into requests of at most 4096 values. SUM is one
encrypted global result through one million values. Above one million, the Job
makes several requests and combines returned partial scalars in the benchmark
client; those rows are labelled `global_scalar_client_combined`. Mean and
variance remain per 4096-value chunk.

## Results

```text
benchmark_runs/compare/<UTC-time>/summary.csv
benchmark_runs/compare/<UTC-time>/result.json
benchmark_runs/compare/<UTC-time>/job.log
benchmark_runs/compare/<UTC-time>/failures.csv  # only when a limit is hit
```

`summary.csv` has one row per profile, size, operation, and backend. Important
timings are:

| Field | Meaning |
| --- | --- |
| `calculation_seconds` | HE operation only; primary CPU/GPU comparison |
| `encrypt_seconds` | Recorded now for later encryption analysis |
| `encryption_values_per_second` | Plaintext inputs encrypted per second |
| `context_keygen_seconds` | Context and evaluation-key setup |
| `decrypt_seconds` | Backend decryption |
| `backend_total_seconds` | Complete work inside the backend |
| `end_to_end_seconds` | Client-observed HTTP time |

Your external collector can recognize `value_count=50000`. This repository
does not generate the final comparison report.

Monitor with:

```sh
kubectl -n datalake-he get pvc,jobs,pods -w
```
