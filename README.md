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
scripts/argocd/         paused repository, registry, bootstrap, promotion helpers
config/he-lab.env       namespace, images, services, and URLs
k8s/                    renderable CPU/GPU and benchmark YAML templates
scripts/sdk/            installable-wheel smoke test on K3s
scripts/notebook/       deploy and privately open the JupyterLab playground
scripts/postgres/       deploy, migrate, and privately forward PostgreSQL
jobs/                   simple non-benchmark CPU/GPU submission Jobs
docs/                   benchmark and K3s command runbooks
```

All benchmark-related scripts, including direct evaluator deployment, belong
under `scripts/benchmark/`.

Edit `config/he-lab.env` before pushing when the target namespace, Docker Hub
repository/tags, Deployment names, or Service names change. It contains no
secret values. The scripts render the tracked files in `k8s/`; Kubernetes YAML
is no longer embedded inside the shell scripts.

Scripted `kubectl` calls verify the K3s API certificate by default. For a
temporary lab certificate problem only, set
`HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY=true` in `config/he-lab.env`; every helper
then adds `--insecure-skip-tls-verify=true` consistently.

## Build first

Push `k3s-demo-app` and wait for GitLab to publish immutable commit tags plus
the convenience aliases:

```text
docker.io/dockerboi99/he_k8s:cpu-<short-commit-sha>
docker.io/dockerboi99/he_k8s:gpu-<short-commit-sha>
docker.io/dockerboi99/he_k8s:cpu-latest
docker.io/dockerboi99/he_k8s:gpu-latest
```

Use the commit tags for a cached work-server mirror. Do not use `latest` for a
repeatable deployment.

## Direct K3s deployment

Deploy the successful public Docker Hub images:

```sh
./scripts/benchmark/deploy-cpu-service.sh cpu-<cpu-build-short-sha>
./scripts/benchmark/deploy-gpu-service.sh gpu-<gpu-build-short-sha>
```

Each backend Deployment exposes one ClusterIP Service for `add`, `subtract`,
`multiply`, `square`, `sum`, `mean`, and population `variance`. No Pod IP or port-forward is needed
for in-cluster clients.

Full commands, verification, and optional Traefik access are in
[docs/k3s-direct-deployment.md](docs/k3s-direct-deployment.md).

## Install and test the SDK wheel

For the simplest interactive path on the server, let CI build the JupyterLab
image and deploy it to K3s:

```sh
./scripts/notebook/deploy.sh notebook-<app-build-short-sha>
./scripts/notebook/open.sh
```

The notebook executes the SDK directly in Python/OpenFHE and does not call
PostgreSQL, HTTP evaluators, or GPU workers. The full guide is in
[`docs/he-notebook-playground.md`](docs/he-notebook-playground.md); the tracked
source notebook is [`notebooks/he_playground.ipynb`](notebooks/he_playground.ipynb).

The immutable CPU image also contains the CI-built wheel. Test that wheel as a
normal Python library first:

```sh
python scripts/sdk/test_sdk.py
```

The selected Python environment must already contain the SDK wheel and its
pinned OpenFHE dependency. The container-based command that requires no host
OpenFHE installation is documented in
[`docs/he-sdk-smoke.md`](docs/he-sdk-smoke.md).

After that passes, test it inside K3s independently from the HTTP evaluator
Service:

```sh
./scripts/sdk/run-smoke.sh cpu-<app-build-short-sha>
```

The Job installs `/opt/he-sdk-wheel/he_looming_sdk-*.whl` into a temporary `emptyDir`
and executes all seven OpenFHE SDK functions. No CUDA, compiler, OpenFHE build,
or package download is required on the K3s host. See
[`docs/he-sdk-smoke.md`](docs/he-sdk-smoke.md).

## PostgreSQL storage

Deploy the CI-built PostgreSQL image with a persistent volume, private
ClusterIP Service, generated credential Secret, and the current HE schema:

```sh
./scripts/postgres/deploy.sh
./scripts/postgres/forward.sh
```

Schema migrations run on every deployment and preserve existing rows. The SDK
does not write to PostgreSQL automatically yet. See
[`docs/he-postgres-storage.md`](docs/he-postgres-storage.md).

## Benchmarks

The current goal, trust boundary, CPU/GPU split, benchmark meaning, and known
SUM limitation are summarized in
[docs/what-we-are-building.md](docs/what-we-are-building.md).

The unified comparison runs Python, CPU, and GPU on the same values:

```sh
./scripts/benchmark/compare/prepare-data.sh \
  --count 10000 --data-profiles positive_decimal_3 --seed 42
./scripts/benchmark/compare/run.sh \
  --operations sum --sizes 5000 10000 \
  --data-profiles positive_decimal_3
```

Sizes, operation selection, output fields, and the separate encrypted-contract
benchmark are documented in
[docs/he-benchmark-commands.md](docs/he-benchmark-commands.md). The GPU path is
implemented but remains experimental until it passes on the target NVIDIA
server.
