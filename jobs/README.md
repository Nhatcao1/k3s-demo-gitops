# Simple HE computation Jobs

These are normal one-request submission Jobs, not benchmarks. The HE evaluator
Service must already be deployed. A trusted client prepares an encrypted
`request.json`; the Job sends it to either CPU or GPU and writes the encrypted
JSON response to the Job log.

The request must never contain plaintext or a secret key. CPU requests contain
the serialized context and ciphertexts. GPU requests additionally contain the
public key required by FIDESlib.

For a small trial, put the prepared request in the ConfigMap and submit one Job:

```sh
kubectl -n he-dev create configmap he-compute-request \
  --from-file=request.json=./data/request.json \
  --dry-run=client -o yaml | kubectl apply -f -

job=$(kubectl create -f jobs/cpu-evaluate-job.yaml -o name)
kubectl -n he-dev wait --for=condition=complete "$job" --timeout=10m
kubectl -n he-dev logs "$job"
```

For GPU, use `jobs/gpu-evaluate-job.yaml` instead. The output remains encrypted;
the trusted client is responsible for decryption.

This ConfigMap input is intentionally only for small trials and is limited to
about 1 MiB. Use a PVC or object storage later for large ciphertext artifacts;
that input/output contract is not fixed yet.
