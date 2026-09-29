# HE GPU notebook playground

This is the simplest interactive path for using the HE SDK on the Kubernetes
T4 node. The Notebook Pod runs JupyterLab and calls the FIDES backend directly;
it does not call PostgreSQL, an evaluator Service, or a batch worker.

The application image contains the complete matching environment:

```text
Python 3.12
JupyterLab
he_looming_sdk
he-sdk-fides
FIDESlib + patched OpenFHE
CUDA runtime
gpu_sdk_example.ipynb
```

The source notebook is maintained in the application repository at:

```text
k3s-demo-app/examples/notebooks/gpu_sdk_example.ipynb
```

GitOps does not maintain another copy. During deployment, the init container
copies the notebook bundled in the image to the workspace PVC.

## 1. Build the image

In the `k3s-demo-app` GitLab pipeline, enable optional builds and run
`build-he-notebook-gpu`. The job publishes:

```text
docker.io/dockerboi99/he_k8s:notebook-gpu-<short-commit-sha>
docker.io/dockerboi99/he_k8s:notebook-gpu-latest
```

The CI runner compiles and packages the GPU environment but does not execute a
GPU operation. Use the immutable commit tag for deployment.

## 2. Deploy to K3s

Run from `k3s-demo-gitops` on a host with working `kubectl` access:

```sh
git pull --ff-only origin main

export HE_NAMESPACE=datalake-he
export HE_IMAGE_REPOSITORY=docker.io/dockerboi99/he_k8s
export HE_NOTEBOOK_GPU_NODE_NAME=hht-k8s-staging-22
export HE_NOTEBOOK_GPU_TAINT_VALUE=T4

./scripts/notebook/deploy.sh notebook-gpu-<short-commit-sha>
```

The script creates or updates:

- the Jupyter access-token Secret;
- a 2 GiB workspace PVC;
- a T4-pinned GPU Deployment;
- a private ClusterIP Service.

There is no automatic HE test at Pod startup. The container starts JupyterLab,
and the user creates the FIDES session by running the example notebook.

## 3. Open JupyterLab

Keep this command running on the Kubernetes-access host:

```sh
export HE_NAMESPACE=datalake-he
./scripts/notebook/open.sh
```

It prints a URL containing the token:

```text
http://127.0.0.1:18888/lab?token=...
```

If the browser is on another computer, create an SSH tunnel from that computer:

```sh
ssh -L 18888:127.0.0.1:18888 <user>@<k3s-server>
```

Then open `http://127.0.0.1:18888/lab`.

## 4. Run the example

Open:

```text
gpu_sdk_example.ipynb
```

Run its cells from top to bottom. The notebook performs only straightforward
SDK calls:

1. import `HESession` and the FIDES plugin;
2. create one `HESession(backend="fides")`;
3. encrypt two small vectors;
4. call add, subtract, multiply, square, sum, mean, and variance;
5. decrypt and print each result;
6. close the session.

There are no benchmarks, helper frameworks, assertions, or package-install
cells in the notebook.

## Notebook persistence

On every deployment, the image copy is written to:

```text
/workspace/gpu_sdk_example.latest.ipynb
```

The editable file is created only when it does not already exist:

```text
/workspace/gpu_sdk_example.ipynb
```

This keeps user edits on the PVC while still exposing the newest image version
as the `.latest.ipynb` file.

## Status and logs

```sh
kubectl -n datalake-he get pod,service,pvc | grep he-notebook
kubectl -n datalake-he logs deployment/he-notebook -c jupyterlab --tail=100
kubectl -n datalake-he describe pod -l app=he-notebook
```

Common failures:

- `ImagePullBackOff`: the requested immutable image tag was not published.
- Pod `Pending`: check the T4 node name, taint, and `nvidia.com/gpu` capacity.
- `CrashLoopBackOff`: inspect the JupyterLab container log.
- A notebook cell fails when creating the session: inspect CUDA driver and
  FIDESlib compatibility on the GPU node.

## Stop the notebook

Stop GPU usage while keeping the PVC:

```sh
kubectl -n datalake-he scale deployment/he-notebook --replicas=0
```
