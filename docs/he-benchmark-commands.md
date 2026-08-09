# HE demo benchmark commands

This runner compares the same generated CKKS values with:

```text
Python baseline -> CPU OpenFHE demo API -> GPU FIDESlib demo API
```

It runs inside Kubernetes and calls the existing ClusterIP Services. No
port-forward, server virtual environment, or local OpenFHE installation is
needed. It does not rebuild either HE library.

## 1. Deploy once

Set the image repository and immutable CPU/GPU tags in `config/he-lab.env`,
then run:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-cpu-service.sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/deploy-gpu-service.sh

kubectl -n datalake-he rollout status deployment/he-evaluator-cpu --timeout=10m
kubectl -n datalake-he rollout status deployment/he-evaluator-gpu --timeout=15m
```

## 2. Quick check

The default profile is `positive_decimal_3`:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations sum \
  --sizes 1000
```

Use this run order:

| Job | Operations | Sizes | Profiles |
| --- | --- | --- | --- |
| 1. Smoke | `sum` | `1000` | `positive_decimal_3` |
| 2. SUM scale | `sum` | `50000 100000 500000 1000000` | all ten |
| 3. Other functions | one or a small group at a time | `1000 4096 50000` first | one profile, then all ten |
| 4. Large trial | selected passing operations | up to `10000000` | selected profiles |

## 3. Run several input sizes in one Job

One command creates one Kubernetes Job and processes every requested size:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations sum \
  --sizes 1000 50000 100000 500000 1000000 \
  --data-profiles positive_decimal_3 \
  --repetitions 3 \
  --timeout 3600
```

Start with SUM. Add other operations only after the smaller run passes:

```sh
HE_NAMESPACE=datalake-he ./scripts/benchmark/compare/run.sh \
  --operations add subtract multiply square sum mean variance \
  --sizes 1000 4096 50000 \
  --data-profiles positive_decimal_3 \
  --repetitions 1 \
  --timeout 3600
```

## 4. Run the sign and decimal profiles

All values stay within `[-40000, 40000]`. Available profiles are:

```text
positive_integer       negative_integer
positive_decimal_1     negative_decimal_1
positive_decimal_2     negative_decimal_2
positive_decimal_3     negative_decimal_3
positive_decimal_6     negative_decimal_6
```

Several profiles can run in the same Job:

```sh
HE_NAMESPACE=datalake-he BENCH_JOB_TIMEOUT_SECONDS=43200 \
  ./scripts/benchmark/compare/run.sh \
  --operations sum \
  --sizes 50000 100000 500000 1000000 \
  --data-profiles \
    positive_integer negative_integer \
    positive_decimal_1 negative_decimal_1 \
    positive_decimal_2 negative_decimal_2 \
    positive_decimal_3 negative_decimal_3 \
    positive_decimal_6 negative_decimal_6 \
  --seed 42 \
  --repetitions 3 \
  --timeout 3600
```

`--data-profiles all` is the shorter equivalent. It can be expensive when
combined with all seven operations, so test one profile and small sizes first.

## What the demo API does

For `add`, `subtract`, `multiply`, `square`, `mean`, and `variance`, the Job
splits inputs into at most 4096 values and calls:

```text
POST /v1/demo/evaluate
```

For SUM it calls the large-vector endpoint:

```text
POST /v1/demo/sum
```

Plaintext enters these trusted demo endpoints. Each backend performs its own
CKKS context/key creation, encryption, HE evaluation, and decryption. This is
for convenient correctness and performance testing; the production-style
secretless ciphertext contract remains `/v1/evaluate`.

SUM is one encrypted global result through one million values. Above one
million, the Job makes several requests and combines returned partial scalars
in the benchmark client; such rows are labelled
`global_scalar_client_combined`. Mean and variance remain per 4096-value chunk.

## Results

```text
benchmark_runs/compare/<UTC-time>/summary.csv
benchmark_runs/compare/<UTC-time>/result.json
benchmark_runs/compare/<UTC-time>/job.log
```

The summary has one row per profile, size, operation, and backend. Your
external collector can recognize `value_count=50000`; this repository does not
generate the final comparison report.

The exact fields are documented in
[`benchmark-data-contract.md`](benchmark-data-contract.md).

Monitor a running Job with:

```sh
kubectl -n datalake-he get jobs,pods -w
```
