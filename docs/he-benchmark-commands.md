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
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh cpu-<commit>
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh gpu-<commit>
```

The data-preparation and comparison scripts never apply or restart evaluator
Deployments. They read the exact live CPU/GPU image references and reject
`cpu-latest`, `gpu-latest`, and plain `latest`. By default, the data generator
and comparison client reuse the live immutable CPU image. An explicit
`HE_COMPARE_DATA_IMAGE` or `HE_COMPARE_IMAGE` override must also be immutable.

CPU and GPU use their own encryptors inside their existing demo Service:

```text
CPU: OpenFHE-Python encrypt -> calculate -> decrypt
GPU: FIDESlib C++ encrypt -> calculate -> decrypt
```

There is no extra shared encryptor Pod. The response reports encryption time
separately, while `calculation_seconds` remains the main operation-performance
measurement.

### Configure benchmark Job resources

All evaluator and benchmark resource defaults are in `config/he-lab.env`.
The benchmark-side groups are:

```text
HE_BENCH_*          generic primitive benchmark client
HE_SUM_BENCH_*      legacy SUM comparison client
HE_COMPARE_*        CPU/GPU/Python comparison client
HE_COMPARE_DATA_*   reusable CSV data-generator Job and PVC
```

Each Job group has CPU/memory requests and limits plus a temporary-storage
size. `HE_COMPARE_DATA_*` controls the bounded-data PVC, `HE_STRESS_DATA_*`
controls the billion-range stress PVC, and
`HE_COMPARE_JOB_TTL_SECONDS` controls cleanup of completed comparison/data
Jobs. These settings change only the benchmark Pods; evaluator resources use
`HE_CPU_*` and `HE_GPU_*`.

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

Normal profiles use `he-comparison-data` (`10Gi`). Billion-range stress
profiles use the separate `he-stress-data` PVC (`100Gi`). Change
`HE_COMPARE_DATA_PVC` / `HE_COMPARE_DATA_STORAGE` or
`HE_STRESS_DATA_PVC` / `HE_STRESS_DATA_STORAGE` in `config/he-lab.env` when
needed. The scripts select the PVC from `--data-profiles`; the cluster must
have a default StorageClass.

Running the same preparation command again verifies and reuses matching files.
Use `--force` only when you intentionally want to regenerate them. If a later
run needs two million values, prepare again with `--count 2000000`; every
profile keeps stable deterministic prefixes for A and B.

For the two billion-range stress profiles, a larger `--count` appends only the
missing rows to the existing CSV and then updates its metadata/checksum. For
example, extending 1,000 rows to 10 million continues at 1,001; it does not
rewrite the first 1,000 rows. Do not use `--force` when extending.

The preparation and comparison scripts delete their Job/Pod only after logs
and result files are captured; the PVC and CSV data are never deleted. Before
a new run, finished Jobs from older script versions are removed so a
ReadWriteOnce Ceph/RBD volume can detach from its previous node. A still-active
Job blocks the new run instead of creating a second Pod that cannot mount the
same volume. Kubernetes TTL cleanup defaults to ten minutes through
`HE_COMPARE_JOB_TTL_SECONDS`.

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

The `stress` group contains only two new integer profiles. It does not include
the decimal profiles used by the regular `all` group:

```text
stress_positive_integer_1b:  1, 2, 3, ... 1000000000, 1, ...
stress_negative_integer_1b: -1,-2,-3, ...-1000000000,-1, ...
```

These files live on `he-stress-data`, separate from every existing
`[-40000, 40000]` random and sequential dataset on `he-comparison-data`.
Preparing stress data therefore cannot overwrite the older tests. The
requested row count controls how far the sequence is materialized; for
example, ten million rows contain `1..10000000` in each direction.

Prepare one ten-million-row prefix on the dedicated stress PVC. This does not
delete or replace any random-profile CSV on the normal PVC:

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

The older bounded sequential profiles remain available by their explicit
names, such as `sequential_positive_integer` or
`sequential_positive_decimal_3`; they are no longer part of the `stress`
shortcut.

Before every load or backend attempt, the runner writes a recoverable marker.
Normal Python/HTTP exceptions become explicit failure records. If Kubernetes
kills the process outright, such as `OOMKilled`, `run.sh` combines the last
attempt marker with Pod termination details. Completed sizes remain in
`summary.csv`; the first failed limit is written to `failures.csv` and
`result.json`.

`--sizes` has no artificial upper ceiling; every value only needs to be a
positive integer. The prepared PVC dataset must contain at least the largest
requested size. Very large runs are expected to stop naturally at storage,
memory, timeout, API, or cluster limits, and the last attempted case is kept in
the failure outputs above.

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
benchmark_runs/compare/<operations>/<UTC-time>/summary.csv
benchmark_runs/compare/<operations>/<UTC-time>/result.json
benchmark_runs/compare/<operations>/<UTC-time>/job.log
benchmark_runs/compare/<operations>/<UTC-time>/failures.csv  # only on failure
```

`<operations>` reflects the command, for example `sum`, `square`, `add`, or
`add-square`. The default is `all`.

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

The value-range multiplication test (`1×2...1×N`, `2×2...2×N`) is documented
separately in [`he-multiply-range-benchmark.md`](he-multiply-range-benchmark.md).
It generates chunks in memory and does not use either benchmark-data PVC.

Small ciphertext correctness checks for the real `POST /v1/evaluate` endpoint
are separate from benchmarks. See
[`he-evaluate-api-tests.md`](he-evaluate-api-tests.md).

The no-PVC SUM numeric-range test through 100 billion is documented in
[`he-sum-range-benchmark.md`](he-sum-range-benchmark.md).
