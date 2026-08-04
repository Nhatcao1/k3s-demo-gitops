# Primitive and SUM commands

```sh
cd ~/gitlab-k3s-lab/k3s-demo-gitops
export HE_REPO="$HOME/Desktop/Viettel/end2end_homecredit_lgbm"
cd "$HE_REPO"
source .venv-openfhe/bin/activate
cd ~/gitlab-k3s-lab/k3s-demo-gitops
```

Prepare the full installments data once. This recreates the prepared folder:

```sh
./scripts/prepare-he-bench-data.sh
```

Start with 50k:

```sh
./scripts/run-he-bench.sh cpu primitive 50000
./scripts/run-he-bench.sh cpu sum 50000
```

Run 50k, 100k, 500k, 1m, and 10m:

```sh
./scripts/run-he-bench.sh cpu primitive all
./scripts/run-he-bench.sh cpu sum all
```

Use five repetitions later:

```sh
REPETITIONS=5 ./scripts/run-he-bench.sh cpu sum 500000
```

Results go to `$HE_REPO/benchmark_runs/`. The 10m case needs much more RAM, so
run it after smaller sizes pass.

GPU uses the same future command format, but is intentionally disabled until
the FIDESlib worker implements real primitive and SUM execution. The current
GPU image only proves that FIDESlib builds and links.
