# HE multiplication range benchmark

This benchmark tests increasing multiplication values rather than increasing
CSV row counts:

```text
base 1: 1×2, 1×3, ... 1×N
base 2: 2×2, 2×3, ... 2×N
```

Every product is independent and consumes one ciphertext multiplication
level. This tests numeric range/accuracy and throughput; it is not chained
multiplication such as `(((2×2)×3)×4)`, which would instead stress
multiplicative depth.

It generates at most `--chunk-size` values in memory, calls the deployed CPU
and GPU `POST /v1/demo/evaluate` multiply operation, and compares every output
with the exact integer product. It does not create or mount a data PVC.

## Run

Start small:

```sh
HE_NAMESPACE=datalake-he \
./scripts/benchmark/multiply-range/run.sh \
  --scheme CKKS \
  --bases 1 2 \
  --start-factor 2 \
  --max-factor 1000000 \
  --chunk-size 4096 \
  --checkpoint-size 100000 \
  --abs-tolerance 0.1 \
  --rel-tolerance 0.000001 \
  --timeout 3600
```

Increase only `--max-factor` after that run succeeds. A checkpoint is emitted
after each configured factor interval, so completed ranges remain recoverable
if a later request or Pod fails.

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
  --chunk-size 4096 \
  --checkpoint-size 100000 \
  --timeout 3600
```

BGV defaults to zero absolute and relative error tolerance and therefore stops
on its first incorrect integer. The CPU demo plaintext modulus is
`4000350209`, with centered signed range approximately `±2000175104`, covering
the default maximum product `2×1000000000`. The pinned FIDESlib GPU backend is
CKKS-only, so BGV is intentionally CPU-only.
