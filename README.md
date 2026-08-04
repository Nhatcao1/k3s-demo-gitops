# HE K3s GitOps lab

Desired K3s development state for the HE application in the companion GitLab
repository:

```text
k3s-demo-app HE commit
  -> GitLab CI tests and builds an immutable image
  -> this repository promotes that exact commit tag
  -> Argo CD reconciles he-dev on K3s
```

The old counter application remains available in Git history but is no longer
part of the desired state.

## Next milestone: encrypted-only evaluator and test bench

The current manifests deploy the trusted gateway trial. The next change will
replace that workload with a secretless CPU evaluator and a separate encrypted
test-client Job. The client generates keys, encrypts, calls the evaluator,
decrypts the returned ciphertext and writes the benchmark result; plaintext
and the secret key never enter the evaluator Pod.

See
[docs/encrypted-he-deployment.md](docs/encrypted-he-deployment.md) for the
exact manifest ownership, separate CPU/GPU run procedure, result collection
and delivery checklist. The document is a target contract; the current YAML
does not satisfy it yet.

## Layout

```text
apps/he/base/          reusable trusted HE gateway resources
apps/he/overlays/dev/  development image tag and hostname
argocd/                he-lab project and he-dev Application
benchmarks/he/          shared CPU/GPU trial sizes and backend status
scripts/               validation, registry, promotion, and status helpers
```

For the short server commands that prepare data once and run the 50k through
10m primitive/SUM cases, see
[docs/he-benchmark-commands.md](docs/he-benchmark-commands.md).

## First deployment order

First commit and push the HE application repository. Its successful default
branch pipeline publishes:

```text
registry.gitlab.com/nhatcao99uetwork/k3s-demo-app/openfhe-gateway:<full-commit-sha>
```

Promote that full SHA here:

```sh
./scripts/promote-he-image.sh <full-k3s-demo-app-commit-sha>
./scripts/validate.sh
```

Create a read-only GitLab deploy token with `read_registry`, then create the
K3s pull secret:

```sh
./scripts/create-registry-secrets.sh
```

Review, commit, and push the GitOps changes only after the image exists.

## Argo CD

Give Argo CD read access to this private GitOps repository:

```sh
ssh-keygen -t ed25519 \
  -C "argocd-he-gitops" \
  -f "$HOME/.ssh/id_ed25519_argocd_gitops"

./scripts/register-argocd-repo.sh \
  "$HOME/.ssh/id_ed25519_argocd_gitops"
```

Bootstrap or update the root application:

```sh
./scripts/bootstrap.sh
./scripts/status.sh
```

The installed root Application temporarily keeps its existing Kubernetes name
`counter-root` so this migration updates it in place instead of creating two
root controllers. It now manages only `he-lab` and `he-dev`. Both root and
development applications use automatic sync, pruning, and self-healing.

## Access

Point the development hostname to a K3s node running Traefik:

```text
100.121.1.22 he-dev.k3s.test
```

Verify:

```sh
curl http://he-dev.k3s.test/healthz
curl http://he-dev.k3s.test/v1/capabilities
```

The PostSync Job uses `HEClient` against the in-cluster gateway and checks real
OpenFHE subtraction, addition, multiplication, sum, and mean results. It fails
the Argo operation when any decrypted result is incorrect.

## Current scope

- one trusted gateway replica with in-memory sessions;
- one immutable image per GitLab application commit;
- GitLab Container Registry for the K3s lab;
- add, subtract, multiply, sum, and mean only;
- no variance, min/max, dot product, or scoring functions;
- `he_k8s` remains separate for the later production-server path.
