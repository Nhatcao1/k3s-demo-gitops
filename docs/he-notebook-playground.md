# HE GPU notebook playground

This is the direct interactive GPU interface for experimenting with the SDK.
The browser talks to JupyterLab, and Python calls the FIDES backend on the T4
assigned to the same Pod. PostgreSQL, the evaluator HTTP API, batch workers,
and Ingress are not part of this path.

```mermaid
flowchart LR
    A[Browser] -->|kubectl port-forward + token| B[JupyterLab Service]
    B --> C[Notebook Pod]
    C --> D[he_looming_sdk + he-sdk-fides]
    D --> E[FIDESlib + CUDA T4]
    E --> F[Encrypted operation]
    C <--> G[(Workspace PVC)]
```

## 1. Build the image in GitLab CI

Push the `k3s-demo-app` feature commit that contains the `sdk-notebook` target
in `gpu/Dockerfile`. The manual `build-he-notebook-gpu` job uses the wheel from
`build-sdk-wheel` and publishes:

```text
docker.io/dockerboi99/he_k8s:notebook-gpu-<short-commit-sha>
docker.io/dockerboi99/he_k8s:notebook-gpu-latest
```

The self-hosted GitLab runner does not need a GPU: it compiles CUDA/FIDESlib and
packages JupyterLab, the core SDK wheel, and the FIDES plugin wheel. It does not
create a FIDES session or claim GPU correctness. Wait for the build job to
succeed, then deploy the immutable `notebook-gpu-<short-commit-sha>` tag. The
first actual GPU correctness check happens during Pod startup on K3s.

## 2. Deploy to K3s

Run from the `k3s-demo-gitops` checkout on the server that has working
`kubectl` access:

```sh
git pull --ff-only origin main
./scripts/notebook/deploy.sh notebook-gpu-<short-commit-sha>
```

The deploy helper creates or updates:

- one Secret containing the Jupyter access token;
- one ConfigMap containing the tracked playground notebook;
- one 2 GiB workspace PVC;
- one T4-pinned GPU JupyterLab Deployment and one ClusterIP Service.

The Pod requests one `nvidia.com/gpu`, uses `runtimeClassName: nvidia`, selects
the configured GPU node, and tolerates its dedicated T4 taint. Before starting
JupyterLab, it runs a real `HESession` FIDES
`encrypt -> square -> decrypt` preflight. A failure stops the container and is
reported automatically with Pod logs and scheduling events; it never falls
back to OpenFHE CPU.

This direct playground keeps its trusted FIDES keys in the Notebook process.
The current local FIDES session does not serialize workspaces or perform
result-release key conversion. Use the separate OpenFHE owner + GPU batch Job
flow in `docs/he-sdk-workloads.md` when those boundaries are required.

The first deployment generates a random token. To provide your own token on
that first run, use:

```sh
HE_NOTEBOOK_TOKEN='<long-random-token>' \
  ./scripts/notebook/deploy.sh notebook-gpu-<short-commit-sha>
```

The token is stored only in Kubernetes, not in Git. Later deploys preserve it.

## 3. Open JupyterLab

On the machine where you want the local browser connection, run:

```sh
./scripts/notebook/open.sh
```

The script prints a `http://127.0.0.1:18888/lab?token=...` URL and keeps the
port-forward running. Open that URL and keep the terminal open. The Service is
not exposed through Ingress or a public `NodePort`.

If your browser is on a different computer from the K3s server, create an SSH
tunnel first:

```sh
ssh -L 18888:127.0.0.1:18888 <user>@<k3s-server>
```

Then run `./scripts/notebook/open.sh` on the server and open
`http://127.0.0.1:18888/lab` on your computer. Paste the printed token if
Jupyter asks for it.

## 4. Use the playground

Open `he_playground.ipynb` and run cells from top to bottom:

1. Import `HESession` and define two small vectors.
2. Create one FIDES GPU session. Context and key generation may take noticeably
   longer than a normal Python import.
3. Run the direct `encrypt -> square -> decrypt` example.
4. Change `OPERATION` to `add`, `subtract`, `multiply`, `square`, `sum`, `mean`,
   or `variance` and run that cell again.
5. Set `RUN_ALL = True` only when you want the full seven-operation check.
6. Close the session when finished, then shut down the kernel from JupyterLab.

CKKS results are approximate, so the notebook checks numeric tolerance rather
than exact float equality.

## Persistence and notebook updates

Your editable `he_playground.ipynb` lives on the PVC and survives Pod restarts.
Every deployment also writes the newest Git version as
`he_playground.latest.ipynb`. This prevents a GitOps update from overwriting
your experiments. Copy cells from the latest file when you want to adopt an
updated template.

## Checks and troubleshooting

```sh
kubectl -n he-dev get pod,service,pvc | grep he-notebook
kubectl -n he-dev logs deployment/he-notebook -c jupyterlab --tail=100
kubectl -n he-dev describe pod -l app=he-notebook
```

- `ImagePullBackOff`: verify that the CI job published the exact immutable tag.
- `Pending` PVC: verify that the K3s cluster has a default storage class (the
  normal K3s `local-path` provisioner is sufficient).
- Pod `Pending`: confirm the configured T4 node name/taint and that
  `nvidia.com/gpu` is allocatable.
- `CrashLoopBackOff`: inspect the JupyterLab container log. A missing driver,
  CUDA/FIDES mismatch, or failed encrypted preflight is intentionally fatal.
- Pod not ready: confirm the GPU node has enough CPU and RAM for FIDES context
  and key generation.
- Token rejected: delete only `secret/he-notebook-auth` and rerun deploy to
  generate a new one. Existing notebook files on the PVC are unaffected.

## Stop or remove

Stop compute while retaining notebook files:

```sh
kubectl -n he-dev scale deployment/he-notebook --replicas=0
```

Deleting the PVC permanently deletes saved notebooks, so it is intentionally
not part of the normal cleanup instructions.
