# HE SDK GPU notebook

The notebook source now belongs to the application image:

```text
k3s-demo-app/examples/notebooks/gpu_sdk_example.ipynb
```

The same image contains Python 3.12, JupyterLab, `he_looming_sdk`,
`he-sdk-fides`, CUDA/FIDESlib, and the native binding. GitOps copies that
bundled notebook into the workspace PVC before starting JupyterLab, so there is
no second notebook implementation to keep synchronized here.

Deploy and open it with:

```sh
./scripts/notebook/deploy.sh notebook-gpu-<app-build-short-sha>
./scripts/notebook/open.sh
```

See [`docs/he-notebook-playground.md`](../docs/he-notebook-playground.md).
