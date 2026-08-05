# Direct K3s deployment commands

Argo CD is intentionally skipped for this phase. These commands deploy the
CPU OpenFHE evaluator directly with `kubectl`.

One Deployment and one ClusterIP Service handle all four operations:
`add`, `subtract`, `multiply`, and `sum`. Do not create separate primitive and
SUM services.

## 1. Select the application image

The tracked non-secret defaults are in `config/he-lab.env`. Edit that file
before pushing when the target namespace, image repository, or tags change.
The default CPU image is:

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops

export HE_IMAGE="docker.io/dockerboi99/he_k8s:cpu-latest"
```

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

It performs the Deployment, resource, Service, and rollout commands shown
below and sets `imagePullPolicy: Always` so `cpu-latest` is refreshed from
Docker Hub instead of using a stale node cache.

```sh
kubectl -n he-dev create deployment he-evaluator-cpu \
  --image="$HE_IMAGE" \
  --port=8080 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n he-dev set image deployment/he-evaluator-cpu \
  "he-evaluator-cpu=$HE_IMAGE"

kubectl -n he-dev set resources deployment/he-evaluator-cpu \
  --requests=cpu=1,memory=2Gi \
  --limits=cpu=4,memory=8Gi

kubectl -n he-dev rollout status deployment/he-evaluator-cpu \
  --timeout=10m
```

## 4. Create the stable in-cluster Service

```sh
kubectl -n he-dev create service clusterip he-evaluator \
  --tcp=8080:8080 \
  --dry-run=client -o yaml | kubectl apply -f -
```

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
