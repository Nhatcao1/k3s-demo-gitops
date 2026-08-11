# Direct K3s deployment commands

Argo CD is intentionally skipped for this phase. The helper scripts apply
tracked Kubernetes templates directly with `kubectl`.

One Deployment and one ClusterIP Service per backend handle all seven operations:
`add`, `subtract`, `multiply`, `square`, `sum`, `mean`, and population
`variance`. Do not create a
separate Service for each operation.

## 1. Select the application image

The tracked non-secret defaults are in `config/he-lab.env`. Edit that file
before pushing when the namespace, image repository, tags, Deployment names,
Service names, or port change. The scripts use those values automatically:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
sed -n '1,200p' config/he-lab.env
```

The actual resources are in:

```text
k8s/cpu-evaluator.yaml
k8s/gpu-evaluator.yaml
k8s/benchmark-job.yaml
k8s/sum-benchmark-job.yaml
k8s/he-comparison-job.yaml
k8s/he-comparison-data-job.yaml
```

Edit probes and volume definitions in YAML. Keep evaluator resources,
benchmark Job resources, temporary-storage sizes, and comparison PVC size in
`config/he-lab.env` so every script renders the same server settings.

### Evaluator CPU, memory, and GPU limits

The defaults in `config/he-lab.env` are:

```sh
: "${HE_CPU_REQUEST_CPU:=1}"
: "${HE_CPU_REQUEST_MEMORY:=2Gi}"
: "${HE_CPU_LIMIT_CPU:=4}"
: "${HE_CPU_LIMIT_MEMORY:=8Gi}"

: "${HE_GPU_REQUEST_CPU:=2}"
: "${HE_GPU_REQUEST_MEMORY:=4Gi}"
: "${HE_GPU_LIMIT_CPU:=8}"
: "${HE_GPU_LIMIT_MEMORY:=16Gi}"
: "${HE_GPU_COUNT:=1}"
```

Requests reserve scheduler capacity; limits cap container usage. Leave
`HE_GPU_COUNT=1` unless one evaluator Pod is intentionally meant to own more
than one GPU. Apply changes by rerunning the corresponding deploy script.

Benchmark clients and the reusable-data source Job have separate resource
groups: `HE_BENCH_*`, `HE_SUM_BENCH_*`, `HE_COMPARE_*`, and
`HE_COMPARE_DATA_*`. Changing those values affects the next benchmark Job and
does not restart either evaluator Deployment.

Comparison storage is also split here: bounded profiles use
`HE_COMPARE_DATA_PVC` / `HE_COMPARE_DATA_STORAGE`, while billion-range stress
profiles use `HE_STRESS_DATA_PVC` / `HE_STRESS_DATA_STORAGE`.

### Optional K3s TLS workaround

All repository scripts verify the Kubernetes API certificate by default. If a
temporary lab cluster fails specifically with an `x509` certificate error,
change this setting in `config/he-lab.env`:

```sh
: "${HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY:=true}"
```

Every scripted `kubectl` call will then use
`--insecure-skip-tls-verify=true`. Return it to `false` after fixing the K3s
kubeconfig CA; this setting does not affect Docker image pulls or GitLab SSH.

## 2. Create the namespace

The deployment helper creates the configured namespace when it does not
already exist:

```sh
kubectl get namespace he-dev >/dev/null 2>&1 || kubectl create namespace he-dev
```

## 3. Create or update the evaluator Deployment

The short repeatable command is:

```sh
./scripts/benchmark/deploy-cpu-service.sh cpu-<cpu-build-short-sha>
```

It renders `k8s/cpu-evaluator.yaml` using `config/he-lab.env`, applies the
Deployment and Service, and deploys the immutable CI tag. Use
`gpu-<gpu-build-short-sha>` with `deploy-gpu-service.sh`. CPU and GPU build jobs
may come from different commits. Avoid moving `latest` tags on a registry
mirror because its cache may continue returning an older digest.

## 4. Stable in-cluster Service

The same CPU YAML creates the ClusterIP Service. No separate Service command
is needed.

Pods and benchmark Jobs inside `he-dev` use this stable URL:

```text
http://he-evaluator:8080
```

They do not use Pod IPs and do not require `kubectl port-forward`.

## Direct health, capability, and SUM calls

These commands send `[12, 7, 8, 9]` directly to each deployed service. Both
services encrypt the values inside their own runtime, perform the SUM on
ciphertext, decrypt once, and return a result close to `36`.

### CPU OpenFHE-Python

Keep this running in terminal 1:

```sh
kubectl -n datalake-he port-forward service/he-evaluator 18080:8080
```

Call the CPU service from terminal 2:

```sh
curl -fsS -X POST http://127.0.0.1:18080/v1/demo/sum \
  -H 'Content-Type: application/json' \
  -d '{"values":[12,7,8,9]}' | python3 -m json.tool
```

### GPU FIDESlib

Stop the CPU port-forward with `Ctrl-C`, then keep this running in terminal 1:

```sh
kubectl -n datalake-he port-forward service/he-evaluator-gpu 18081:8080
```

Check the deployed image API from terminal 2:

```sh
curl -fsS http://127.0.0.1:18081/healthz
curl -fsS http://127.0.0.1:18081/readyz
curl -fsS http://127.0.0.1:18081/v1/capabilities | python3 -m json.tool
```

The capabilities response must list all seven main operations:

```text
add, subtract, multiply, square, sum, mean, variance
```

Then call the small plaintext SUM demo:

```sh
curl -fsS -X POST http://127.0.0.1:18081/v1/demo/sum \
  -H 'Content-Type: application/json' \
  -d '{"values":[12,7,8,9]}' | python3 -m json.tool
```

The CPU path calls OpenFHE `EvalSum`; the GPU path starts the native
`he-gpu-demo` executable, which calls FIDESlib `AccumulateSum`. These are
trusted functional checks, not the final secretless ciphertext API.

### FIDESlib endpoints exposed by the GPU Service

All paths below use the same `he-evaluator-gpu` Deployment and Service:

| Method and path | Purpose |
| --- | --- |
| `GET /healthz` | HTTP process is alive |
| `GET /readyz` | GPU runtime and native workers are ready |
| `GET /v1/capabilities` | Runtime backend and supported operations |
| `POST /v1/evaluate` | Main ciphertext API: `add`, `subtract`, `multiply`, `square`, `sum`, `mean`, `variance` |
| `POST /v1/demo/evaluate` | Small plaintext HE demo for the same seven operations |
| `POST /v1/demo/sum` | Large plaintext-input SUM benchmark helper |

`variance` means population variance `E[x²] - E[x]²`. It requires both
`multiplication_keys` and `rotation_keys` in `/v1/evaluate`; older single-key
operations may continue using `evaluation_keys`.

The demo route accepts plaintext and performs key generation, encryption, HE
evaluation, and decryption inside its native backend. It proves that the image,
GPU runtime, and HE operation work. It does not prove the secretless boundary.
A trusted client creates and serializes CKKS artifacts for `/v1/evaluate` and
keeps the secret key outside the evaluator Pod.

The required development sequence for each new function is:

```text
backend operation
  -> /v1/evaluate ciphertext contract
  -> /v1/demo/evaluate quick diagnostic
  -> direct curl/client correctness check
  -> benchmark case and saved timing result
```

`square` request shape:

```json
{
  "operation": "square",
  "context": "<base64 FIDESlib-compatible OpenFHE context>",
  "public_key": "<base64 public key>",
  "ciphertext_a": "<base64 input ciphertext>",
  "evaluation_keys": "<base64 multiplication/relinearization keys>",
  "request_id": "square-demo-1"
}
```

`mean` request shape:

```json
{
  "operation": "mean",
  "context": "<base64 FIDESlib-compatible OpenFHE context>",
  "public_key": "<base64 public key>",
  "ciphertext_a": "<base64 input ciphertext>",
  "evaluation_keys": "<base64 rotation/automorphism keys>",
  "valid_count": 8192,
  "request_id": "mean-demo-1"
}
```

Submit a generated request file through the forwarded GPU port:

```sh
curl -fsS -X POST http://127.0.0.1:18081/v1/evaluate \
  -H 'Content-Type: application/json' \
  --data-binary @gpu-request.json | python3 -m json.tool
```

The response contains a Base64 result `ciphertext`; it does not contain the
plaintext result or a secret key. The client must deserialize and decrypt it.

Quick GPU variance demo through the port-forward above:

```sh
curl -sS -X POST http://127.0.0.1:18081/v1/demo/evaluate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"variance","values_a":[1,2,3,4]}'
```

The decrypted population variance should be approximately `1.25`.

## Known image-pull error: 2026-08-06

- The exact GitLab tag was `gpu-7d830d6f` (8 characters), not the 7-character
  local Git display `gpu-7d830d6`.
- `http: server gave HTTP response to HTTPS client` from
  `hub.vtcc.vn:8989` means containerd tried HTTPS against a mirror serving
  HTTP. It does not mean Docker Hub lacks the image.
- Use `docker.io/dockerboi99/he_k8s:<exact-tag>` when direct Docker Hub HTTPS
  works. Otherwise a cluster administrator must configure the mirror as plain
  HTTP on every target node. A Kubernetes TLS-skip flag or imagePullSecret
  cannot repair this node-runtime protocol mismatch.

## 5. Optional external access through K3s Traefik

Create an Ingress only when the API must be reached outside the cluster:

```sh
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: he-evaluator
  namespace: he-dev
spec:
  ingressClassName: traefik
  rules:
    - host: he-dev.k3s.test
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: he-evaluator
                port:
                  number: 8080
YAML
```

Point `he-dev.k3s.test` to a K3s node in the client machine's `/etc/hosts`,
then verify:

```sh
curl -fsS http://he-dev.k3s.test/healthz
curl -fsS http://he-dev.k3s.test/v1/capabilities
```

## Status and logs

```sh
kubectl -n he-dev get deployment,pods,service,ingress -o wide
kubectl -n he-dev logs deployment/he-evaluator-cpu --tail=100
```

Run the implemented benchmark Jobs with:

```sh
./scripts/benchmark/run-he-bench.sh cpu primitive 50000
./scripts/benchmark/run-he-bench.sh cpu sum 50000

# Pandas vs CPU demo SUM vs GPU demo SUM in one in-cluster Job
./scripts/benchmark/sum/run.sh --sizes 50000 --repetitions 1
```

The first two commands call `http://he-evaluator:8080/v1/evaluate` from inside
`he-dev`. Argo CD will be reintroduced only after the direct CPU deployment and
benchmarks pass.

The combined SUM command calls the CPU and GPU `/v1/demo/sum` ClusterIP URLs
from its benchmark Pod. It does not use `port-forward`, does not request a GPU
for the client, and works when the Kubernetes API proxy rejects upgraded
connections. The GPU resource remains owned only by `he-evaluator-gpu`.

## GPU deployment

The GPU path follows the same pattern and reads its values from
`config/he-lab.env`:

```sh
kubectl get nodes \
  -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

./scripts/benchmark/deploy-gpu-service.sh
./scripts/benchmark/run-he-bench.sh gpu primitive 50000
```

The GPU container now checks the NVIDIA driver and device count before starting
the HTTP API. The deploy script prints pod logs automatically when startup or
rollout fails. This avoids relying on `kubectl exec`, which may be blocked by a
cluster proxy that does not support streaming upgrade connections.

For an evaluation error after a successful startup, inspect the worker detail:

```sh
kubectl -n he-dev logs -l app=he-evaluator-gpu --tail=200 --prefix=true
```

`GPU runtime check passed` means Kubernetes and the NVIDIA runtime are working.
A later `FIDESlib worker exited` line identifies a worker/build or serialized
artifact compatibility failure.

`k8s/gpu-evaluator.yaml` requests one `nvidia.com/gpu`. It cannot become Ready
unless K3s advertises that resource and the configured GPU image exists.

The GPU Deployment uses the `Recreate` strategy because the selected node has
one allocatable GPU. During an update Kubernetes stops the old Pod first, then
starts the new Pod with `gpu-latest`; a normal rolling update would leave the
replacement Pending while the old Pod continued holding the only GPU.

For deterministic lab refreshes, `deploy-gpu-service.sh` also deletes the old
GPU Deployment and waits for its Pod to disappear before applying the tracked
template. The ClusterIP Service is preserved and selects the newly created Pod.
The deploy script uses `HE_GPU_IMAGE` directly from `config/he-lab.env`, so a
restricted work server never needs to contact Docker Hub. Set that value to an
immutable mirror digest if the mirror caches the moving `gpu-latest` tag.

The work-server scheduling rules are written directly in
`k8s/gpu-evaluator.yaml`:

```text
container runtime class: nvidia
required node hostname: hht-k8s-staging-22
tolerated node taint: dedicated=T4:NoSchedule
```

Only the GPU evaluator gets this node selector and toleration. The benchmark client
does not request a GPU. Confirm the target node before deployment:

```sh
kubectl get node hht-k8s-staging-22 -o custom-columns='NAME:.metadata.name,CORDONED:.spec.unschedulable,GPU:.status.allocatable.nvidia\.com/gpu,TAINTS:.spec.taints'
kubectl get runtimeclass nvidia
kubectl describe node <gpu-node-name> | grep -A5 Taints
```

Edit that GPU YAML only if a different server uses different labels or taints.

### Native FIDESlib examples

Run the native C++ examples before testing the HTTP adapter. Their commands,
YAML files, expected behavior, and development plan are documented in
`fides-examples/README.md`:

```sh
./fides-examples/run.sh simple
```

The Job requests one GPU on `hht-k8s-staging-22`. If the evaluator Deployment
already owns the node's only GPU, temporarily release it and restore it after
the test:

```sh
kubectl -n he-dev scale deployment/he-evaluator-gpu --replicas=0
./fides-examples/run.sh simple
kubectl -n he-dev scale deployment/he-evaluator-gpu --replicas=1
kubectl -n he-dev rollout status deployment/he-evaluator-gpu --timeout=15m
```

If this native test fails, the problem is CUDA/FIDESlib/T4 rather than the
Python API or serialized-artifact bridge. If it passes, debug the bridge next.
