# Real `/v1/evaluate` functional tests

These are small correctness tests, not benchmarks. Each test does the complete
ciphertext flow:

```text
create CKKS context and keys in trusted test Job
  -> encrypt fixed inputs
  -> POST serialized ciphertext to /v1/evaluate
  -> save returned ciphertext in PVC
  -> decrypt in trusted test Job
  -> print expected, decrypted, error, PASS/FAIL
```

The evaluator receives neither plaintext nor the secret key. The secret key
exists only in Job memory and disappears when that Job exits. The PVC stores
the serialized context, public/evaluation keys, encrypted inputs, encrypted
result, and a small result-status JSON without plaintext values. Expected and
decrypted values are printed only in the Job log. This is lab storage, not
production key or ciphertext management.

## 1. Create the artifact PVC once

```sh
./scripts/evaluate-api/setup.sh
```

The default PVC is `he-evaluate-api-artifacts` in `HE_NAMESPACE`. Test Jobs are
scheduled on the same Kubernetes node as the CPU evaluator to avoid moving the
ReadWriteOnce volume between nodes. With a `WaitForFirstConsumer` storage
class, `Pending` immediately after setup is normal; the first test Job binds it.

## 2. Run one function

CPU:

```sh
./scripts/evaluate-api/add.sh cpu
./scripts/evaluate-api/subtract.sh cpu
./scripts/evaluate-api/multiply.sh cpu
./scripts/evaluate-api/square.sh cpu
./scripts/evaluate-api/sum.sh cpu
./scripts/evaluate-api/mean.sh cpu
./scripts/evaluate-api/variance.sh cpu
```

GPU uses the same trusted OpenFHE client and sends the additional public key
advertised by the FIDESlib API:

```sh
./scripts/evaluate-api/add.sh gpu
./scripts/evaluate-api/multiply.sh gpu
./scripts/evaluate-api/sum.sh gpu
```

To run all seven sequentially:

```sh
./scripts/evaluate-api/run-all.sh cpu
./scripts/evaluate-api/run-all.sh gpu
```

Each successful log contains fields similar to:

```json
{
  "status": "PASS",
  "operation": "add",
  "expected": [2.0, 3.0, 2.0, 6.0],
  "decrypted": [2.0000001, 2.9999999, 2.0, 6.0],
  "result_ciphertext_bytes": 123456,
  "secret_key_sent_to_evaluator": false,
  "plaintext_sent_to_evaluator": false
}
```

Artifacts remain under this PVC layout:

```text
/he-artifacts/<cpu|gpu>/<operation>/<UTC-run-id>/
  context.bin
  public-key.bin
  multiplication-keys.bin
  rotation-keys.bin
  ciphertext-a.bin
  ciphertext-b.bin
  result-ciphertext.bin
  result.json
```

The tests intentionally fail if deserialization, the evaluator operation,
decryption, or the CKKS tolerance check fails. A GPU failure here can reveal a
real standard-OpenFHE versus FIDESlib-patched-OpenFHE artifact compatibility
problem that the plaintext demo endpoint cannot detect.
