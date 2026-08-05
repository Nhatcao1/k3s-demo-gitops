# Paused Argo CD helpers

These scripts belong to the saved Argo CD workflow and are not required for
the current direct CPU/GPU deployment from public Docker Hub images.

When the Argo phase resumes:

```sh
# Required only while apps/he uses the private GitLab registry.
./scripts/argocd/create-registry-secrets.sh

# Register the private GitOps repository and create the root Application.
./scripts/argocd/register-argocd-repo.sh
./scripts/argocd/bootstrap.sh

# Update the immutable GitLab image tag in the saved development overlay.
./scripts/argocd/promote-he-image.sh <k3s-demo-app-commit-sha>
```

`bootstrap.sh` intentionally preserves the existing `counter-root` Application
name during the migration to the HE lab. Review the saved `argocd/` and
`apps/he/` manifests before resuming automatic synchronization.

These helpers also honor `HE_KUBECTL_INSECURE_SKIP_TLS_VERIFY` from
`config/he-lab.env`. Keep it `false` unless the lab Kubernetes API currently
has an `x509` certificate problem.
