# HE SDK notebook playground

This is the shortest interactive path for exercising the SDK directly on the
K3s T4. The notebook does not call PostgreSQL, an HTTP evaluator, or a batch
worker; its `HESession` uses the FIDES backend in the Notebook Pod.

The recommended path for a weak local computer is the CI-built K3s deployment:

```sh
./scripts/notebook/deploy.sh notebook-gpu-<app-build-short-sha>
./scripts/notebook/open.sh
```

See [`docs/he-notebook-playground.md`](../docs/he-notebook-playground.md) for
the complete build, deploy, access, usage, persistence, and troubleshooting
guide.

Do not install packages from a notebook cell. The GitLab-built image already
contains JupyterLab, the checked SDK wheel, its FIDES plugin, and the matching
CUDA/FIDESlib runtime. A normal local Python environment is not equivalent.

The notebook creates one `HESession` and reuses it. Start with the direct
`square` example, then change `OPERATION` to `add`, `subtract`, `multiply`,
`square`, `sum`, `mean`, or `variance`.

FIDES context and key generation dominate startup time. Smaller input vectors
make the operation easier to inspect but do not remove that fixed setup cost.
