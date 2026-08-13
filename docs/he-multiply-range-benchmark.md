# HE multiplication range benchmark

This benchmark samples increasing multiplication values rather than increasing
CSV row counts. Power-of-two sampling is the safe default:

```text
base 1: 1×2, 1×4, 1×8, ... 1×N
base 2: 2×2, 2×4, 2×8, ... 2×N
```

If `N` is not a power of two, the exact `N` is appended as the final sample.
This makes a one-billion limit about 30 samples per base/backend instead of one
billion samples.

Every product is independent and consumes one ciphertext multiplication
level. This tests numeric range/accuracy and throughput; it is not chained
multiplication such as `(((2×2)×3)×4)`, which would instead stress
multiplicative depth.

It generates at most `--chunk-size` values in memory, calls the deployed CPU
and GPU `POST /v1/demo/evaluate` multiply operation, and compares every sampled
output with the exact integer product. It does not create or mount a data PVC.

## Run

Start small:

```sh
HE_NAMESPACE=datalake-he \
./scripts/benchmark/multiply-range/run.sh \
  --scheme CKKS \
  --bases 1 2 \
  --start-factor 2 \
  --max-factor 1000000000 \
  --powers-of-two \
  --chunk-size 4096 \
  --checkpoint-size 10 \
  --abs-tolerance 0.1 \
  --rel-tolerance 0.000001 \
  --timeout 3600
```

`--powers-of-two` is optional because it is the default when no sampling flag
is supplied. `--checkpoint-size` counts tested samples, not every skipped
integer. Completed checkpoints remain recoverable if a later request fails.

For a fixed interval instead, use:

```sh
./scripts/benchmark/multiply-range/run.sh \
  --scheme CKKS \
  --bases 1 2 \
  --start-factor 2 \
  --max-factor 1000000000 \
  --step 10000000 \
  --checkpoint-size 10 \
  --timeout 3600
```

The exact maximum is also appended when the step does not land on it. Use
`--step 1` only for deliberately small exhaustive ranges.

The CKKS run stops immediately when:

- both absolute and relative CKKS tolerances are exceeded for one product;
- CPU/GPU returns an HTTP/runtime error;
- Kubernetes terminates or times out the Job.

Results are stored in:

```text
benchmark_runs/multiply-range/<UTC-time>/result.json
benchmark_runs/multiply-range/<UTC-time>/summary.csv
benchmark_runs/multiply-range/<UTC-time>/failures.csv  # on failure
benchmark_runs/multiply-range/<UTC-time>/job.log
```

## Run BGV on CPU

After deploying the CPU image whose capabilities include BGV:

```sh
HE_NAMESPACE=datalake-he \
./scripts/benchmark/multiply-range/run.sh \
  --scheme BGV \
  --bases 1 2 \
  --start-factor 2 \
  --max-factor 1000000000 \
  --powers-of-two \
  --chunk-size 4096 \
  --checkpoint-size 10 \
  --timeout 3600
```

BGV defaults to zero absolute and relative error tolerance and therefore stops
on its first incorrect integer. The CPU demo plaintext modulus is
`4000350209`, with centered signed range approximately `±2000175104`, covering
the default maximum product `2×1000000000`. The pinned FIDESlib GPU backend is
CKKS-only, so BGV is intentionally CPU-only.
