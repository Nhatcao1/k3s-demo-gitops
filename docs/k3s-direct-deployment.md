# Direct K3s deployment commands

Argo CD is intentionally skipped for this phase. The helper scripts apply
tracked Kubernetes templates directly with `kubectl`.

One Deployment and one ClusterIP Service handle all CPU operations:
`add`, `subtract`, `multiply`, `multiply_plain`, `square`, `sum`, `mean`, and
population `variance`. Do not create a Service per function.

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
```

Edit resources, probes, and volumes in YAML. Do not put Kubernetes YAML back
inside the shell scripts.

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

The deployment helper creates `he-dev` when it does not already exist. The
Docker Hub repository is public, so this direct path needs no registry secret:

```sh
kubectl get namespace he-dev >/dev/null 2>&1 || kubectl create namespace he-dev
```

## 3. Create or update the evaluator Deployment

The short repeatable command is:

```sh
./scripts/benchmark/deploy-cpu-service.sh
```

For the feature build containing the Postgres demo and the new functions, use
its immutable short tag:

```sh
./scripts/benchmark/deploy-cpu-service.sh cpu-8d51c282
```

It renders `k8s/cpu-evaluator.yaml` using `config/he-lab.env`, applies the
Deployment and Service, and restarts the Deployment so a moving `cpu-latest`
tag is pulled again.

## 4. Stable in-cluster Service

The same CPU YAML creates the ClusterIP Service. No separate Service command
is needed.

Pods and benchmark Jobs inside `he-dev` use this stable URL:

```text
http://he-evaluator:8080
```

They do not use Pod IPs and do not require `kubectl port-forward`.

Verify from inside the cluster:

```sh
kubectl -n he-dev run he-api-check \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.15.0 \
  --command -- curl -fsS http://he-evaluator:8080/healthz

kubectl -n he-dev run he-capabilities-check \
  --rm -i --restart=Never \
  --image=curlimages/curl:8.15.0 \
  --command -- curl -fsS http://he-evaluator:8080/v1/capabilities
```

For a quick plaintext diagnostic from the K3s server, forward the Service and
call the real OpenFHE demo path:

```sh
kubectl -n he-dev port-forward service/he-evaluator 18080:8080

curl -sS -X POST http://127.0.0.1:18080/v1/demo/evaluate \
  -H 'Content-Type: application/json' \
  -d '{"operation":"mean","values_a":[1,2,3,4]}'
```

Expected `values` is approximately `[2.5]`. See
`demo/cpu-postgres/README.md` for `square` and `variance` commands and for the
important distinction between this plaintext diagnostic and `/v1/evaluate`.

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
```

They call `http://he-evaluator:8080/v1/evaluate` from inside `he-dev`. Argo CD
will be reintroduced only after the direct CPU deployment and benchmarks pass.

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
