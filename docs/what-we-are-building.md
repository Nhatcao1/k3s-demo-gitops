# What we are building and testing

## Goal

Build a small function-as-a-service layer for homomorphic encryption (HE).
An application chooses a normal function such as `add` or `sum`; it should not
need to manage OpenFHE calls, CUDA code, rescaling, or evaluation keys itself.

We are developing one function at a time. The current functions are:

```text
add -> subtract -> multiply -> sum
```

Later candidates are `square`, `mean`, and `variance`. They should not be
added until the current functions are correct and benchmarked.

## Security and service boundary

```text
trusted client Job                         evaluator Service
------------------                        -----------------
create context and keys
create or load plaintext data
encrypt data
send context + required eval keys + ciphertexts  --------->
                                            evaluate ciphertext only
                                      <--------- result ciphertext
decrypt and verify result
```

The evaluator must never receive plaintext or the secret key. The benchmark
client is trusted because it owns encryption, decryption, and correctness
checking.

The API is currently a low-level encrypted evaluator API:

```text
POST /v1/evaluate
operation = add | subtract | multiply | sum
```

The longer-term API should hide HE parameters behind a reviewable plan. It
must follow our HE parameter rules: CKKS for approximate real numbers, depth
based on the calculation path, automatic scaling, and only the evaluation
keys required by the selected functions.

## CPU and GPU design

Both implementations stay in `k3s-demo-app`, but they are separate images and
separate processes:

| Target | Runtime | Current state |
| --- | --- | --- |
| CPU | standard OpenFHE-Python | service and benchmark available |
| GPU | FIDESlib with its patched OpenFHE | image/backend started; remote ciphertext transport incomplete |

Standard OpenFHE and FIDESlib's patched OpenFHE must never be linked into the
same image or process. A successful CUDA image build is not a GPU benchmark.
GPU results count only after the FIDESlib function executes and a trusted
client verifies the decrypted answer.

## What the benchmark is testing

The benchmark runs as a Kubernetes Job and calls the deployed ClusterIP
Service. It does not call a local OpenFHE session as a substitute for the
service.

For each function it compares:

```text
plain Python operation
versus
client encryption + serialization + HTTP/service evaluation + decryption
```

It records Python time, encryption time, serialization time, service
round-trip time, evaluator time, decryption time, total HE time, slowdown,
throughput, CKKS error, and PASS/FAIL.

The test sizes are:

```text
50k, 100k, 500k, 1m, 10m values
```

Inputs are deterministic and processed in CKKS-sized chunks so CPU and GPU
can later run comparable workloads without loading 10 million Python values
at once.

## Current SUM limitation

For data larger than one ciphertext, the current benchmark calls encrypted
`sum` for every chunk. It then decrypts each chunk result and combines those
partial totals in the trusted client for verification.

This is enough to measure the deployed SUM primitive over the full number of
input values. It is not yet a fully encrypted end-to-end aggregate. That
version must add the encrypted partial sums through the evaluator and perform
only one final client decryption.

## Repository responsibilities

```text
k3s-demo-app
  HE backend functions, HTTP API, tests, Dockerfiles, GitLab image builds

k3s-demo-gitops
  direct K3s deployment, benchmark Jobs, run commands, collected result files
```

Argo CD is intentionally paused while this service and benchmark contract is
stabilized. Benchmark result files stay outside Git through
`benchmark_runs/`.

## Gate before developing more functions

Before adding another HE function:

1. CPU add, subtract, multiply, and sum return correct decrypted results.
2. The 50k test passes first, followed by the larger sizes.
3. No evaluator request or log contains plaintext or a secret key.
4. Timings and accuracy are saved in a reviewable JSON result.
5. The fully encrypted cross-chunk SUM behavior is either implemented or its
   client-side final aggregation remains clearly labelled.
6. GPU performance is not compared until FIDESlib transport and verification
   work end to end.
