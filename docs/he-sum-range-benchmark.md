# SUM numeric-range stress test

This is a numeric-limit test separate from the PVC row-count benchmark. CKKS
runs on CPU and GPU; BGV runs on CPU because FIDESlib GPU is CKKS-only.

For each sampled target SUM, the Job creates only `--sum-value-count` values
in memory whose total equals that target. It therefore reaches 100 billion
without generating or reading 100 billion rows. Targets default to powers of
two, with the exact `--max-sum` appended at the end.

```sh
./scripts/benchmark/sum-range/run.sh \
  --scheme CKKS \
  --backends cpu gpu \
  --start-sum 2 \
  --max-sum 100000000000 \
  --powers-of-two \
  --sum-value-count 4096 \
  --abs-tolerance 0.1 \
  --rel-tolerance 0.000001 \
  --timeout 3600
```

The run stops immediately on the first accuracy, API, timeout, or resource
failure. Results are written to:

```text
benchmark_runs/sum-range/<UTC-run-id>/
```

For fixed sampling instead of powers of two, replace `--powers-of-two` with,
for example, `--step 1000000000`. No PVC preparation is required.

BGV exact-integer SUM on CPU:

```sh
./scripts/benchmark/sum-range/run.sh \
  --scheme BGV \
  --backends cpu \
  --start-sum 2 \
  --max-sum 100000000000 \
  --powers-of-two \
  --sum-value-count 4096 \
  --timeout 3600
```

BGV distributes each target exactly across integer slots and uses zero error
tolerance. It requires the updated CPU evaluator image with BGV SUM support.
The CKKS path does not require a new image.
