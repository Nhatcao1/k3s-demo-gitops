# Encrypted evaluator test contract

Argo CD is paused. The current CPU trial uses direct `kubectl` helpers under
`scripts/benchmark/`.

## Security boundary

```text
benchmark client Job
  creates context and keys
  encrypts deterministic inputs
  sends context + required evaluation keys + ciphertexts
                         ↓
he-evaluator CPU Service
  add | subtract | multiply | sum
  returns ciphertext only
                         ↓
benchmark client Job
  decrypts, checks accuracy, compares with Python baseline
```

The secret key exists only in benchmark client memory. It is not placed in an
HTTP request, Kubernetes Secret, ConfigMap, volume, evaluator environment, or
log. The evaluator receives no plaintext input.

## Current implementation

| Component | Location | Status |
| --- | --- | --- |
| CPU evaluator Deployment and ClusterIP Service | `k8s/cpu-evaluator.yaml` via `deploy-cpu-service.sh` | implemented |
| Service benchmark client | `scripts/benchmark/service_benchmark.py` | implemented |
| Primitive benchmark Job | `scripts/benchmark/run-he-bench.sh cpu primitive ...` | implemented |
| SUM benchmark Job | `scripts/benchmark/run-he-bench.sh cpu sum ...` | implemented |
| GPU evaluator Deployment and Service | `k8s/gpu-evaluator.yaml` via `deploy-gpu-service.sh` | implemented; server verification pending |
| CPU/GPU benchmark Job | `k8s/benchmark-job.yaml` via `run-he-bench.sh` | implemented; GPU server verification pending |
| Argo CD reconciliation | `argocd/` | intentionally paused |

The CPU evaluator and trusted benchmark client currently use the same standard
OpenFHE-Python image but run as separate Pods. Standard OpenFHE and FIDESlib's
patched OpenFHE are never combined in one image or process.

## Required evidence

For each operation and input size, keep:

- Python baseline time;
- client encryption and serialization time;
- service round-trip and evaluator-reported time;
- client decryption and encrypted end-to-end time;
- slowdown versus Python and values per second;
- maximum CKKS absolute/relative error;
- PASS/FAIL, chunk count, and confirmation that no secret key was sent.

Sizes are `50k`, `100k`, `500k`, `1m`, and `10m`. Run CPU and GPU separately;
the GPU result is accepted only after verification on the NVIDIA server.

## Direct run order

```sh
./scripts/benchmark/deploy-cpu-service.sh

./scripts/benchmark/run-he-bench.sh cpu primitive 50000
./scripts/benchmark/run-he-bench.sh cpu sum 50000
```

Only after both 50k Jobs pass:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive all
./scripts/benchmark/run-he-bench.sh cpu sum all
```

Detailed commands are in `docs/he-benchmark-commands.md`.

## Remaining backlog

- [x] Deploy one secretless CPU evaluator Service without Argo CD.
- [x] Add manual primitive and SUM Kubernetes benchmark Jobs.
- [x] Compare service HE timing with matching Python operations.
- [x] Record client encryption, service evaluation, decryption, and accuracy.
- [ ] Run and retain 50k CPU primitive/SUM evidence on the K3s server.
- [ ] Run representative larger sizes, ending with 10m.
- [ ] Inspect evaluator logs for plaintext, secret keys, or request payloads.
- [x] Add the GPU evaluator transport and benchmark Job.
- [ ] Run and retain the 50k GPU primitive/SUM evidence on the NVIDIA server.
- [ ] Return to immutable tags and Argo CD after direct acceptance.

## CPU acceptance

The CPU phase passes only when:

1. the evaluator Deployment rolls out and `/readyz` succeeds;
2. primitive and SUM 50k Jobs finish with `PASS`;
3. every operation remains inside the configured CKKS tolerance;
4. benchmark JSON contains all required performance fields;
5. evaluator logs contain no plaintext, secret keys, or serialized payloads;
6. larger trials complete without Pod eviction or out-of-memory failure.
