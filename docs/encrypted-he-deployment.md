# Encrypted HE evaluator and test-bench deployment contract

## Status

This is the target for the next GitOps implementation. Current `apps/he/`
manifests still deploy the trusted gateway and must not be described as an
encrypted-only evaluator until the changes below pass.

Application code, encryption logic, tests and result-schema validation belong
in `k3s-demo-app`. This repository owns only Kubernetes desired state and
operational helper scripts.

## Target layout

```text
apps/he/
├── base/
│   ├── evaluator-deployment.yaml
│   ├── evaluator-service.yaml
│   ├── evaluator-ingress.yaml
│   ├── encrypted-smoke-test.yaml
│   └── kustomization.yaml
└── overlays/
    └── dev/
        └── kustomization.yaml

jobs/he-benchmark/
├── cpu-sum.yaml
└── gpu-sum.yaml                 # add only after CPU acceptance

scripts/
├── promote-he-images.sh
├── run-cpu-benchmark.sh
├── run-gpu-benchmark.sh         # add later
└── collect-benchmark-result.sh
```

Do not place Python benchmark code in this repository. Kubernetes Jobs invoke
the versioned test-client image built by the application repository.

## Images

The CPU release promotes two images from the same application commit:

```text
registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-evaluator-cpu:<full-commit-sha>
registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-test-client:<full-commit-sha>
```

The future GPU evaluator is independent:

```text
registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/fides-evaluator-gpu:<full-commit-sha>
```

Never promote a GitOps image tag until the corresponding GitLab image job has
succeeded.

## CPU evaluator workload

Run the evaluator as a normal `Deployment` and `Service` in `he-dev`:

```text
replicas: 1
request:  1 CPU, 2 GiB memory
limit:    4 CPU, 8 GiB memory
```

Readiness calls `/readyz`; liveness calls `/healthz`. The evaluator container
receives context, evaluation keys and ciphertext only. It must not mount a
secret key, plaintext fixture or writable shared key directory.

## Encrypted smoke-test Job

The smoke test uses `openfhe-test-client` and runs after the evaluator is
ready. It must:

1. generate the deterministic plaintext fixture and reference result;
2. generate the OpenFHE context, keypair and SUM evaluation keys;
3. encrypt inside the client Pod;
4. send only context, evaluation keys and ciphertext to the evaluator Service;
5. decrypt the returned ciphertext inside the client Pod;
6. fail when the accuracy tolerance is exceeded;
7. write `/artifacts/summary.json` and a compact final status to logs.

Use `emptyDir` for ephemeral client artifacts. Do not store the secret key in
Git, a ConfigMap, a Kubernetes Secret or evaluator storage.

The small smoke test can remain an Argo CD `PostSync` hook. The controlled
performance Jobs below are manual and are not included in the application
Kustomization.

## Separate CPU and GPU benchmark Jobs

CPU and GPU do not run in one Pod and do not write the same physical file.
They share only the logical run contract:

```text
run_id, workload, input seed, input count, fixture hash
warm-up count, measured count, accuracy tolerance, result schema
```

Run sequentially on the test cluster to avoid resource interference:

```text
CPU evaluator + CPU client Job -> cpu.json
GPU evaluator + GPU client Job -> gpu.json
node2 comparison script        -> comparison.md
```

Store collected evidence on node2:

```text
benchmark_results/<run-id>/
├── cpu.json
├── gpu.json
└── comparison.md
```

Do not use the K3s `local-path` PVC as a cross-node CPU/GPU exchange: it is
node-local. For the first lab, keep each completed Job Pod and copy its
`summary.json` to node2 before deleting the Job. Object or RWX storage can be
added later only if needed.

## Initial direct run procedure

Argo CD is not required to prove the first CPU benchmark. After pulling this
repository on node2, the equivalent direct flow is:

```sh
kubectl apply -k apps/he/overlays/dev
kubectl rollout status deployment/he-evaluator-cpu -n he-dev

kubectl delete job he-sum-cpu -n he-dev --ignore-not-found
kubectl apply -f jobs/he-benchmark/cpu-sum.yaml
kubectl wait --for=condition=complete job/he-sum-cpu \
  -n he-dev --timeout=30m
```

The collection helper resolves the completed Pod and copies
`/artifacts/summary.json` to a caller-supplied local path. Do not delete the Job
until collection succeeds.

## Implementation backlog

- [ ] Replace trusted gateway Deployment with CPU evaluator Deployment.
- [ ] Replace gateway Service/Ingress targets with CPU evaluator targets.
- [ ] Promote evaluator and test-client image tags together.
- [ ] Replace plaintext gateway smoke test with encrypted client PostSync Job.
- [ ] Add manual CPU SUM benchmark Job and result-collection helper.
- [ ] Validate that the evaluator Pod has no secret-key or plaintext inputs.
- [ ] Complete CPU smoke, accuracy and representative-size evidence.
- [ ] Add GPU Deployment/Job only after CPU acceptance.
- [ ] Run GPU with the same fixture contract and produce `comparison.md`.

## Acceptance

The CPU deployment is accepted only when:

1. evaluator readiness and liveness pass;
2. the encrypted smoke Job completes with `PASS`;
3. the evaluator rejects plaintext and missing evaluation keys;
4. the CPU benchmark emits a schema-valid `cpu.json`;
5. Pod logs contain no plaintext, secret key or serialized request payload;
6. GitOps references immutable images from the same application commit.
