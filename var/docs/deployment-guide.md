# Deployment Guide

Full workflow for this lab:

1. Provision local VM with k3s
2. Lint
3. Build and push image
4. Deploy app + monitoring + ELK
5. Validate

## 1. Prerequisites

On host:
- VirtualBox
- Vagrant
- task

In VM (installed by bootstrap):
- Docker
- kubectl
- helm + helmfile
- sops + gcloud
- task

## 2. Provision VM

```bash
cd var/vagrant
task up
```

Useful commands:

```bash
task status
task ssh
task provision
```

If files changed on host and VM uses rsync:

```bash
VAGRANT_CWD=var/vagrant vagrant rsync
```

## 3. Enter VM

```bash
cd var/vagrant
task ssh
# inside VM:
cd /home/vagrant/observability-lab
```

## 4. Lint

```bash
task lint:all
```

Or individually:

```bash
task lint:docker
task lint:shell
```

## 4.1 Setup SOPS + GCP KMS

```bash
# install tools (if not installed yet)
task bootstrap:sops-gcp

# place your key in keys/gcp-service-account.json (gitignored, never commit)
# optional hidden path also works: .keys/gcp-service-account.json

# auth with local plain service account file (gitignored)
task sops:auth SA_FILE=keys/gcp-service-account.json

# test decrypt access for all *.enc.sops.*
task sops:validate
```

## 5. Build image

```bash
task deploy:image-build IMAGE_TAG=dev
```

Manual:

```bash
docker build --build-arg PORT=8080 -t docker.io/<dockerhub-user>/observability-lab:dev .
```

## 6. Push image

```bash
export DOCKERHUB_USER=<dockerhub-user>
task deploy:image-push IMAGE_TAG=dev
```

If you do not want token in env, store it in SOPS file:

```bash
ci/secrets/dockerhub.enc.sops.yaml
```

Used keys:
- `DOCKERHUB_USER`
- `DOCKERHUB_TOKEN`
- `GHCR_USER` (optional)
- `GHCR_TOKEN` (optional)

Quick create/update example:

```bash
cat > /tmp/registry-secrets.yaml <<EOF
DOCKERHUB_USER: "<dockerhub-user>"
DOCKERHUB_TOKEN: "<dockerhub-token>"
GHCR_USER: "<github-user-or-org>"
GHCR_TOKEN: ""
EOF
bash var/scripts/with-sops-gcp.sh sops --encrypt --filename-override ci/secrets/dockerhub.enc.sops.yaml /tmp/registry-secrets.yaml > ci/secrets/dockerhub.enc.sops.yaml
rm -f /tmp/registry-secrets.yaml
```

Optional GHCR push (same build):

```bash
export ENABLE_GHCR_PUSH=1
export GHCR_USER=<github-user-or-org>
export GHCR_TOKEN=<github-token-with-packages-write>
bash ci/scripts/push.sh
```

For GitHub Actions deploy with SOPS+KMS, add:

```bash
GCP_SA_KEY_B64=<base64-service-account-json>
```

## 7. Deploy to k3s

Default `dev` context resolves to `default`.

Full stack:

```bash
task deploy:all ENV=dev KUBE_CONTEXT=default DOCKERHUB_USER=<dockerhub-user> IMAGE_TAG=dev
```

`monitoring:apply` auto-imports `monitoring/grafana-dashboard.json`.
`elk:apply` auto-imports `elk/kibana-dashboard.json`.

App only:

```bash
task k8s:apply ENV=dev KUBE_CONTEXT=default DOCKERHUB_USER=<dockerhub-user> IMAGE_TAG=dev
```

Check status:

```bash
task deploy:status ENV=dev KUBE_CONTEXT=default
```

## 8. Access services

Ingress (Traefik):

```bash
task ingress:apply ENV=dev KUBE_CONTEXT=default CONTROLLER=traefik
task ingress:status ENV=dev KUBE_CONTEXT=default CONTROLLER=traefik
```

Add local DNS on host if needed:

```text
192.168.56.10 observability-app.local grafana.local kibana.local
```

Then:

```text
http://observability-app.local
http://grafana.local
http://kibana.local
```

Or inside VM via port-forward:

```bash
task monitoring:pf-grafana ENV=dev KUBE_CONTEXT=default
task monitoring:pf-prometheus ENV=dev KUBE_CONTEXT=default
task elk:pf-kibana ENV=dev KUBE_CONTEXT=default
```

## 9. Validate

```bash
task validate:all ENV=dev KUBE_CONTEXT=default
task validate:inspect ENV=dev KUBE_CONTEXT=default
```

HPA load test:

```bash
task validate:hpa-scale ENV=dev KUBE_CONTEXT=default
```

## 10. Redeploy (no VM rebuild)

```bash
VAGRANT_CWD=var/vagrant vagrant rsync
cd /home/vagrant/observability-lab
task lint:all
task deploy:image-build IMAGE_TAG=dev
task deploy:image-push IMAGE_TAG=dev DOCKERHUB_USER=<dockerhub-user>
task deploy:all ENV=dev KUBE_CONTEXT=default DOCKERHUB_USER=<dockerhub-user> IMAGE_TAG=dev
task validate:all ENV=dev KUBE_CONTEXT=default
```

## 11. Optional GitHub self-hosted runner

Inside VM:

```bash
cd /home/vagrant/observability-lab
task runner:init
```

Edit `var/github-runner/.env` and set:
- `REPO_URL`
- `RUNNER_TOKEN`

Then:

```bash
task runner:up
task runner:status
task runner:logs
```

## 12. Troubleshooting

- Provisioning incomplete:
  - `cd var/vagrant && task provision`
- `helmfile apply` fails with `unknown command "diff" for "helm"`:
  - `sudo task bootstrap:all`
- `context "default" does not exist`:
  - re-run task, it auto-exports kubeconfig
  - or manually: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
- Pods not picking up new image:
  - pass `DOCKERHUB_USER` + `IMAGE_TAG` explicitly
- Inspect rollout:
  - `task k8s:rollout ENV=dev KUBE_CONTEXT=default`
