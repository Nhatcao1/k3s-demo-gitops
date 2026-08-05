# Native FIDESlib GPU examples

This folder runs selected upstream FIDESlib C++ examples directly as
Kubernetes Jobs. It bypasses the HTTP API, Python client, and benchmark code,
so it is the shortest check of FIDESlib, CUDA, and the NVIDIA T4.

All examples use the recognizable Docker tag:

```text
docker.io/dockerboi99/he_k8s:gpu-t4-examples
```

## What is included

| Example | Command | What it checks | Expected cost |
| --- | --- | --- | --- |
| `simple` | `./fides-examples/run.sh simple` | CKKS key generation, encrypt, add, subtract, scalar/ciphertext multiply, rotate, decrypt | Small; run first |
| `serial` | `./fides-examples/run.sh serial` | Native context/evaluation-key file round trip followed by CKKS bootstrapping | Heavy; may take several minutes |
| both | `./fides-examples/run.sh all` | Runs `simple`, then `serial` | Run only after `simple` passes |

The tracked Kubernetes files are in `fides-examples/k8s/`. Edit those YAML
files if the GPU node, resource limits, or deadline must change. Shared image
and namespace defaults are in `config/he-lab.env`.

## Run on the GPU cluster

Pull this repository, then temporarily release the GPU if the evaluator is
already using the node's only GPU:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
git pull
kubectl -n he-dev scale deployment/he-evaluator-gpu --replicas=0

./fides-examples/run.sh simple
./fides-examples/run.sh serial
```

Restore the service afterward:

```sh
kubectl -n he-dev scale deployment/he-evaluator-gpu --replicas=1
kubectl -n he-dev rollout status deployment/he-evaluator-gpu --timeout=15m
```

Each command creates one Job, waits for it, then prints its C++ output. No C++
compiler or Python package is needed on the server; both the compiled binaries
and their FIDESlib dependencies are inside the image.

## Development plan

| Stage | Status | Reason |
| --- | --- | --- |
| `simple` | Ready | Establish native CUDA/FIDESlib correctness first |
| `serial` | Ready | Check FIDESlib-native serialization and bootstrap |
| `advanced` | Later | Keep the first trial focused on only two examples |
| `bootstrap` | Later | Heavy and mostly overlaps the first `serial` check |
| BERT, ResNet, logistic regression, HPCA | Later | Require models, datasets, or a separate learning workflow |

Passing `simple` proves the native T4 path works. It does not prove the custom
HTTP worker's serialized OpenFHE input is compatible; that bridge is a separate
test after the native examples pass.
