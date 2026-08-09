# Benchmark data contract and comparison plan

This is the implementation plan for the unified Python/CPU/GPU benchmark.
It distills the supplied benchmark-report template and Chinese comparison
notes without copying those long report tables into this repository.

## Scope and non-goals

The benchmark runner must produce enough raw evidence for a later report. It
does not generate a Vietnamese management report, PDF, chart, conclusion, or
pre-filled comparison table. Missing results stay missing; the runner never
invents or interpolates measurements.

The existing outputs remain the contract:

```text
benchmark_runs/compare/<UTC-time>/summary.csv
benchmark_runs/compare/<UTC-time>/result.json
benchmark_runs/compare/<UTC-time>/job.log
```

`summary.csv` is long-form: one row per operation, backend, and size. A later
reporting step may pivot the `python`, `cpu`, and `gpu` rows. `result.json`
keeps repetitions and service response details for audit.

## Data required from every run

| Field | Purpose |
| --- | --- |
| `operation` | `add`, `subtract`, `multiply`, `square`, `sum`, `mean`, or `variance` |
| `backend` | `python`, `cpu`, or `gpu` |
| `value_count` | Total input values or value pairs |
| `result_scope` | Elementwise, per-chunk scalar, global scalar, or client-combined global scalar |
| `repetitions` | Number of measurements represented by the median row |
| `service_seconds` | Default latency used in the later comparison report |
| `end_to_end_seconds` | Client-observed HTTP time, kept separately |
| `he_compute_seconds` | HE-only timing when the endpoint exposes it; otherwise blank |
| `maximum_absolute_error` | Maximum error against the Python reference |
| `maximum_relative_error` | Diagnostic error retained in raw data |
| `input_min`, `input_max` | Configured generator range |
| `input_value_type` | `float` or `integer` |
| `seed` | Deterministic generator seed |
| `source` | Current value: `deterministic_uniform_generator` |

The raw CSV may continue to contain throughput and accuracy status. A later
report selects only the requested columns; adding report formatting to this
runner is out of scope.

## Input profiles

The runner exposes options rather than hard-coding one dataset:

| Option | Meaning |
| --- | --- |
| `--sizes` | Any positive sizes through 10,000,000 |
| `--min-value`, `--max-value` | Numeric generation range |
| `--value-type float\|integer` | Uniform float or uniform integer values |
| `--seed` | Reproducible input generation |
| `--repetitions` | Median latency input; use at least 3 for reportable runs |
| `--chunk-size` | Non-SUM demo request size, maximum 4096 |
| `--sum-request-size` | Values per `/v1/demo/sum` request, maximum 1,000,000 |

Recommended progression:

1. Correctness: 1,000 values in `0..100`.
2. Chinese-reference input point: 50,000 values in `1..1,000,000`.
3. Scale: 100,000; 500,000; 1,000,000.
4. GPU stress only after smaller runs pass: 10,000,000.
5. Edge ranges are separate runs, for example negative or larger-magnitude
   CKKS inputs; never mix them into the reference run.

For SUM above one million, the runner calls `/v1/demo/sum` repeatedly and
combines the returned partial plaintext scalars with `math.fsum`. The row is
labelled `global_scalar_client_combined`. This measures service work over the
full input but is not fully encrypted aggregation across requests.

## Chinese comparison profile

The supplied comparison has only the 50,000-value point:

| Operation | Published latency | Precision note |
| --- | ---: | ---: |
| `sum` | 0.445–0.535 s | about `1e-6` |
| `mean` | 0.455–0.483 s | about `1e-6` |
| `variance` | 1.798–1.985 s | about `1e-6` |
| sum of squares | less than 0.833 s | about `1e-6` |

The provided material does not identify its generator distribution, seed,
hardware, exact HE parameters, or latency boundary. Our 50,000-value profile
is therefore a labelled reference comparison, not a claim of reproducing the
same experiment. Do not interpolate its latency to other sizes.

Only current global SUM has matching output scope at 50,000 values. Current
`mean` and `variance` produce one scalar per 4096-value chunk, so their 50k
rows are useful internal CPU/GPU measurements but must not be compared with
the published global 50k rows. A matching large-vector HE endpoint/composition
is required first.

`square` returns elementwise squares and must not be compared with the
published sum-of-squares row. That row remains unavailable until a matching
operation/composition is benchmarked.

## Implementation status on this branch

- [x] Keep CSV, JSON, and job log output; do not generate report tables.
- [x] Record input range, value type, seed, and source on summary rows.
- [x] Add deterministic integer generation while retaining float generation.
- [x] Permit sizes through 10 million.
- [x] Split SUM into requests of at most one million and label client combine.
- [x] Document the 50k comparison and wider CPU/GPU commands.
- [ ] Add global large-vector `mean` and `variance` before comparing their
  latency with the published 50k rows.
- [ ] Add a matching sum-of-squares operation/composition before using that
  published row.
- [ ] Run the commands on the GPU cluster and provide the resulting files.
- [ ] Produce a formatted report only when benchmark result files are supplied.
