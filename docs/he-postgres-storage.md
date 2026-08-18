# HE PostgreSQL storage on K3s

This deployment provides one PostgreSQL instance for HE run metadata and
encrypted/public artifacts. It does not store plaintext or HE secret keys, and
the SDK does not write to it automatically yet.

## Deploy or upgrade

The existing Docker Hub image built by `k3s-demo-app` is the default:

```text
docker.io/dockerboi99/he_k8s:postgres-latest
```

Deploy PostgreSQL and apply the current schema:

```sh
./scripts/postgres/deploy.sh
```

On the first run, the script creates a random password in the Kubernetes Secret
`he-postgres-auth`. To select the initial password yourself:

```sh
HE_POSTGRES_PASSWORD='replace-with-a-long-random-password' \
  ./scripts/postgres/deploy.sh
```

Later runs preserve the existing Secret and PVC. They also run an idempotent
schema Job, so schema changes are applied to an initialized database rather
than being ignored by PostgreSQL's first-start initialization behavior.
When an existing column or constraint must change, add an explicit idempotent
`ALTER` statement; `CREATE TABLE IF NOT EXISTS` alone cannot modify a table.

## Access from K3s

Clients in namespace `he-dev` connect to:

```text
host: he-postgres
port: 5432
database: he_store
user: he_app
```

Read credentials from Secret `he-postgres-auth`; do not copy them into an
`.ipynb` file. A future notebook/database integration should expose these as
Pod environment variables from `secretKeyRef`.

## Access from a kubectl host

The Service is not exposed to the Internet. Start a local forward:

```sh
./scripts/postgres/forward.sh
```

Then connect to `127.0.0.1:15432`. Retrieve the password only when needed:

```sh
kubectl -n he-dev get secret he-postgres-auth \
  -o 'jsonpath={.data.POSTGRES_PASSWORD}' | base64 --decode
```

To listen on one Tailscale IP instead, set that exact IP. Anyone able to reach
that IP and port can attempt PostgreSQL authentication, so do not use
`0.0.0.0`:

```sh
HE_POSTGRES_FORWARD_ADDRESS=100.x.y.z ./scripts/postgres/forward.sh
```

## Persistence and schema

The PVC defaults to `he-postgres-data` with `10Gi`. Reapplying or restarting
the StatefulSet preserves its rows. Deleting the PVC deletes the database and
is intentionally not part of any helper script.

Current tables:

- `he_store.runs`: execution state and HE metadata.
- `he_store.artifacts`: ciphertext, context, public key, evaluation key, and
  manifest bytes.

The deployment copy of the schema is
`postgres/schema/001_he_store.sql`. Keep it synchronized with the canonical
application schema in `k3s-demo-app/postgres/init/001_he_store.sql` until the
SDK gains a proper migration package.
