# Benchmark data and result contract

The benchmark reuses the deployed CPU and GPU demo APIs. It does not rebuild
OpenFHE or FIDESlib and it does not generate a final comparison report.

One Kubernetes Job may run several input sizes and data profiles. Reusable CSV
pairs live on a persistent volume and are sent to the Python baseline, CPU
OpenFHE Service, and GPU FIDESlib Service.

## Input bounds and profiles

Regular and older sequential CKKS profiles stay within `[-40000, 40000]`.
The two dedicated integer stress profiles can progress to one billion in each
direction.

| Profile | Values |
| --- | --- |
| `positive_integer` | Positive integers |
| `negative_integer` | Negative integers |
| `positive_decimal_1` / `negative_decimal_1` | Positive/negative values with 1 decimal place |
| `positive_decimal_2` / `negative_decimal_2` | Positive/negative values with 2 decimal places |
| `positive_decimal_3` / `negative_decimal_3` | Positive/negative values with 3 decimal places |
| `positive_decimal_6` / `negative_decimal_6` | Positive/negative values with 6 decimal places |
| `sequential_positive_integer` | Exact `1..40000` sequence, repeated to the requested row count |
| `sequential_negative_integer` | Exact `-1..-40000` sequence, repeated to the requested row count |
| `sequential_positive_decimal_1` / `sequential_negative_decimal_1` | Upward integer sequence with 1 deterministic random fractional digit |
| `sequential_positive_decimal_2` / `sequential_negative_decimal_2` | Upward integer sequence with 2 deterministic random fractional digits |
| `sequential_positive_decimal_3` / `sequential_negative_decimal_3` | Upward integer sequence with 3 deterministic random fractional digits |
| `sequential_positive_decimal_6` / `sequential_negative_decimal_6` | Upward integer sequence with 6 deterministic random fractional digits |
| `stress_positive_integer_1b` | Exact positive integer sequence progressing from `1` to `1000000000` |
| `stress_negative_integer_1b` | Exact negative integer sequence progressing from `-1` to `-1000000000` |

The streaming generator is deterministic for the same profile and seed. For
binary operations it creates independent A and B vectors from the same
profile. A matching file is reused across benchmark runs.

When a billion-range stress CSV exists but is smaller than the requested
count, preparation appends from its recorded count and atomically updates the
metadata file afterward. Existing bounded and legacy sequential files are on
a different PVC and are not modified. `--force` remains the explicit
full-regeneration option.

`--data-profiles all` continues to mean only the original ten random profiles.
`--data-profiles stress` selects only the two new billion-range integer
profiles. The older bounded sequential profiles remain individually
addressable. Normal data uses `he-comparison-data`; stress data uses
`he-stress-data`. Mixing the two families in one Job is rejected because one
Job mounts only its selected PVC.

The runner loads only the current profile/size, emits its result, releases its
arrays, and then loads the next size. It never retains every requested profile
or the maximum-sized arrays for the whole Job.

Benchmark Jobs are removed after their logs/results are collected, while this
PVC remains. Finished legacy Jobs are cleaned before a new run, active Jobs
are treated as an exclusive-PVC conflict, and `ttlSecondsAfterFinished: 600`
is the fallback when the launching shell disappears.

## Result files

```text
benchmark_runs/compare/<UTC-time>/summary.csv
benchmark_runs/compare/<UTC-time>/result.json
benchmark_runs/compare/<UTC-time>/job.log
benchmark_runs/compare/<UTC-time>/failures.csv  # present after a failed limit
```

`summary.csv` contains one row per profile, size, operation, and backend. Its
main fields are:

| Field | Meaning |
| --- | --- |
| `data_profile` | Named sign/precision profile |
| `value_count` | Values, or value pairs for a binary operation |
| `operation` | Demo operation tested |
| `backend` | `python`, `cpu`, or `gpu` |
| `calculation_seconds` | Python or HE operation time; primary comparison |
| `encrypt_seconds` | Backend encryption time, recorded separately |
| `encryption_values_per_second` | Total plaintext inputs encrypted per second |
| `context_keygen_seconds`, `decrypt_seconds` | Other HE lifecycle timings |
| `backend_total_seconds` | Complete backend time |
| `service_seconds` | Compatibility alias for calculation time |
| `end_to_end_seconds` | Full client-observed HTTP time |
| `values_per_second` | `value_count / end_to_end_seconds` |
| `maximum_absolute_error`, `maximum_relative_error` | Error against Python |
| `accuracy_passed` | Configured tolerance result |
| `input_bound_min`, `input_bound_max` | Fixed generator bound |
| `input_min`, `input_max` | Actual minimum and maximum in that test input |
| `input_sign`, `decimal_places`, `seed`, `source`, `dataset_sha256` | Dataset metadata |
| `input_vector_count`, `total_input_values` | Distinguishes unary values from binary value pairs |

Each completed profile/size is emitted before the runner advances, so partial
results can be extracted even if a later case fails. `result.json` also keeps
every completed repetition. The
external result collector may apply its own comparison rules, including any
special handling for rows where `value_count=50000`.

The runner also emits an attempt marker before each load and backend call. A
catchable failure records its operation, backend, size, exception type, and
message. For an uncatchable container termination, the extractor combines the
last attempt with Kubernetes Pod status and records the interrupted size as a
hard limit instead of silently losing it.

## Result scope

| Operation | Current result scope |
| --- | --- |
| `add`, `subtract`, `multiply`, `square` | Element-wise output across chunks |
| `sum` | One global scalar through 1m values; client-combined scalar above 1m |
| `mean`, `variance` | One scalar per 4096-value chunk |

The runner labels these scopes in `result_scope`; it does not present a
per-chunk mean or variance as a global aggregate.
