# HE SDK notebook playground

This is the shortest interactive path for learning the local SDK. The notebook
itself does not call PostgreSQL, an HTTP evaluator, or the GPU backend.

The recommended path for a weak local computer is the CI-built K3s deployment:

```sh
./scripts/notebook/deploy.sh notebook-<app-build-short-sha>
./scripts/notebook/open.sh
```

See [`docs/he-notebook-playground.md`](../docs/he-notebook-playground.md) for
the complete build, deploy, access, usage, persistence, and troubleshooting
guide.

For a machine that can run OpenFHE locally, use:

```sh
python3 -m venv .venv-he-notebook
. .venv-he-notebook/bin/activate
python -m pip install --upgrade pip
python -m pip install jupyterlab openfhe==1.5.1.0.24.4
python -m pip install he_looming_sdk==0.3.1
python -m jupyter lab notebooks/he_playground.ipynb
```

The notebook creates one `HESession` and reuses it. Start with the direct
`square` example, then change `OPERATION` to `add`, `subtract`, `multiply`,
`square`, `sum`, `mean`, or `variance`.

OpenFHE context and key generation dominate startup time. Smaller input vectors
make the operation easier to inspect but do not remove that fixed setup cost.
