# K3s demo GitOps

Desired Kubernetes state for the visit-counter learning lab.

```text
k3s-demo-app commit
  -> GitLab CI builds immutable web/API images
  -> this repository promotes those image tags
  -> Argo CD reconciles K3s
```

Development synchronizes automatically. Production intentionally requires a
manual Argo CD sync so the promotion boundary remains visible.

## Layout

```text
apps/counter/base/          reusable Kubernetes resources
apps/counter/overlays/dev/  development image tags and settings
apps/counter/overlays/prod/ production image tags and settings
argocd/                     AppProject and App-of-Apps definitions
scripts/                    node2 setup and validation helpers
```

The initial image tag in both overlays is `70694d7e`, the first eight characters
of the application repository commit (matching GitLab's
`CI_COMMIT_SHORT_SHA`). Wait for that application's GitLab pipeline to publish
both images before bootstrapping the workloads.

## 1. Validate on node2

Requirements: `kubectl`, access to the K3s cluster, and Argo CD installed in the
`argocd` namespace.

```sh
./scripts/validate.sh
```

## 2. Create registry pull secrets

Create a read-only GitLab deploy token in the application project with
`read_registry`, then run:

```sh
./scripts/create-registry-secrets.sh
```

The script creates `counter-dev` and `counter-prod`, then creates the
`gitlab-registry` pull secret in each. Credentials are read interactively and
are never written to this repository.

## 3. Give Argo CD read access to this private repository

Generate a dedicated key on node2:

```sh
ssh-keygen -t ed25519 \
  -C "argocd-k3s-demo-gitops" \
  -f "$HOME/.ssh/id_ed25519_argocd_gitops"
```

Add the `.pub` file as a read-only deploy key in the GitLab GitOps project,
then register the private key:

```sh
./scripts/register-argocd-repo.sh \
  "$HOME/.ssh/id_ed25519_argocd_gitops"
```

## 4. Bootstrap the App of Apps

```sh
./scripts/bootstrap.sh
./scripts/status.sh
```

`counter-root` manages the `counter-lab` AppProject plus the development and
production Applications.

| Application | Sync behavior |
|---|---|
| `counter-root` | automatic, prune, self-heal |
| `counter-dev` | automatic, prune, self-heal |
| `counter-prod` | manual |

## 5. Promote a new application commit

After both GitLab image jobs succeed:

```sh
./scripts/promote-image.sh <application-short-sha> dev
git add apps/counter/overlays/dev/kustomization.yaml
git commit -m "Deploy application <application-short-sha> to development"
git push origin main
```

Use `prod` only after the development release is verified. Argo CD will show
production as OutOfSync until an operator reviews the diff and synchronizes it.

## Access through Traefik

Point the names at a K3s node running the Traefik ServiceLB:

```text
100.121.1.22 counter-dev.k3s.test
100.121.1.22 counter-prod.k3s.test
```

Then open `http://counter-dev.k3s.test`.

## Secret policy

`counter-lab-secret` contains only a meaningless teaching value. Real
credentials should use an external secret manager, Sealed Secrets, or SOPS and
must never be committed as plaintext.
