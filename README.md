# HE K3s deployment lab

The current phase uses direct `kubectl` deployment. Argo CD files remain in
the repository but are intentionally paused until the CPU service and
benchmarks pass.

```text
k3s-demo-app main branch
  -> GitLab CI builds dockerboi99/he_k8s:cpu-latest
  -> kubectl deploys it to namespace he-dev
  -> clients call http://he-evaluator:8080 inside K3s
```

## Current layout

```text
apps/he/               older gateway manifests; do not apply in this phase
argocd/                saved for the later Argo CD phase
benchmarks/he/          benchmark sizes and operation matrix
scripts/benchmark/      prepare, run, and direct-deployment helpers
docs/                   benchmark and K3s command runbooks
```

All benchmark-related scripts, including direct evaluator deployment, belong
under `scripts/benchmark/`.

## Build first

Push `k3s-demo-app` and wait for GitLab to publish:

```text
docker.io/dockerboi99/he_k8s:cpu-latest
docker.io/dockerboi99/he_k8s:gpu-latest
```

## Direct K3s deployment

Deploy the successful public Docker Hub image:

```sh
./scripts/benchmark/deploy-cpu-service.sh
```

The Deployment exposes one ClusterIP Service for `add`, `subtract`,
`multiply`, and `sum`. No Pod IP or port-forward is needed for in-cluster
benchmark Jobs.

Full commands, verification, and optional Traefik access are in
[docs/k3s-direct-deployment.md](docs/k3s-direct-deployment.md).

## Benchmarks

The current goal, trust boundary, CPU/GPU split, benchmark meaning, and known
SUM limitation are summarized in
[docs/what-we-are-building.md](docs/what-we-are-building.md).

Data preparation and the 50k, 100k, 500k, 1m, and 10m commands are in
[docs/he-benchmark-commands.md](docs/he-benchmark-commands.md).

The CPU benchmarks run as Kubernetes Jobs, call `/v1/evaluate`, and compare
each HE operation with its Python baseline. GPU service testing waits for
FIDESlib ciphertext transport.
