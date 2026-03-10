# observability-lab

SRE/DevOps observability lab. Uses Podinfo with a thin shim to enforce a strict
endpoint and log contract, deployed on k3s with Prometheus + Grafana and ELK.

## Architecture

```text
[Client]
   |
   v
[Service: observability-app:8080]
   |
   v
[Pod: observability-app]
  - container: observability-app (podinfo + shim)
  - endpoints: /health /ready /metrics /request /error /slow

Metrics: app /metrics -> Prometheus -> Grafana

Logs: app stdout JSON -> Filebeat -> Logstash -> Elasticsearch -> Kibana
```

## Endpoints

The app exposes:
- `/health`   liveness
- `/ready`    readiness
- `/metrics`  prometheus
- `/request`  normal traffic
- `/error`    forced 500
- `/slow`     slow response

Each request log includes: `timestamp`, `level`, `endpoint`, `latency`, `APP_ENV`

## Prerequisites

- Docker
- kubectl
- helm + helmfile
- task
- sops
- gcloud (for KMS setup)
- hadolint + shellcheck

## Quick start

```bash
# start VM
cd var/vagrant
task up

# inside VM
vagrant ssh
cd ~/observability-lab
task deploy:all ENV=dev KUBE_CONTEXT=default
```

## Docker

```bash
# build
docker build --build-arg PORT=8080 -t docker.io/rick0x00/observability-lab:latest .

# run
docker run -d --name observability-app-local -p 8080:8080 -e APP_ENV=staging docker.io/rick0x00/observability-lab:latest
```

## Secrets (SOPS + GCP KMS)

Sensitive values are encrypted with SOPS:

- `monitoring/kube-prometheus-stack/secrets.enc.sops.yaml`
- `elk/elasticsearch/secrets.enc.sops.yaml`
- `elk/kibana/secrets.enc.sops.yaml`

Setup flow:

```bash
# install tools in VM
task bootstrap:sops-gcp

# place your local key in keys/gcp-service-account.json (gitignored, never commit)
# optional hidden path also works: .keys/gcp-service-account.json

# auth and kms config
task sops:auth SA_FILE=keys/gcp-service-account.json

# validate decrypt access
task sops:validate
```

Helmfile values use `ref+sops://...` and secrets are resolved at deploy time.

## Kubernetes manifests

```text
k8s/
  deployment.yaml
  service.yaml
  hpa.yaml
  configmap.yaml
  namespace.yaml
  kustomization.yaml
  ingress/observability-app-ingress.yaml
  overlays/
    dev/kustomization.yaml
    stag/kustomization.yaml
    prod/kustomization.yaml
```

- 2 replicas, RollingUpdate
- ConfigMap with `APP_ENV`
- HPA v2: CPU 71%, memory 76%
- Probes: liveness `/health`, readiness `/ready`
- Resources: 100m/128Mi requests, 200m/256Mi limits
- Prometheus annotations: port 8080, path /metrics

## Monitoring

Dashboard export: `monitoring/grafana-dashboard.json`

Panels:
- CPU usage per pod
- Request latency histogram
- Request counter
- Error rate per minute
- P95 latency

## Logging (ELK)

- `elk/logstash.conf`
- `elk/kibana-dashboard.json`
- `elk/kibana-alert-rule.json`

Filebeat collects pod stdout -> Logstash parses JSON -> Elasticsearch.
Index pattern: `app-logs-{environment}-{date}`
Alert: >= 20 errors in 5 min, throttle 5 min.

## CI/CD

Pipeline: `.github/workflows/ci.yml`

Stages: Lint -> Build -> Push -> Deploy

Scripts in `ci/scripts/`. Deploy targets self-hosted/local runner.

Optional GHCR push is supported in `ci/scripts/push.sh` with:
- `ENABLE_GHCR_PUSH=1`
- `GHCR_USER`
- `GHCR_TOKEN`

Docker Hub login for push supports:
- env vars (`DOCKERHUB_USER` + `DOCKERHUB_TOKEN`)
- SOPS file `ci/secrets/dockerhub.enc.sops.yaml`

GHCR push also supports SOPS in the same file:
- `GHCR_USER`
- `GHCR_TOKEN`

You can update this file with:

```bash
bash var/scripts/with-sops-gcp.sh sops --encrypt --filename-override ci/secrets/dockerhub.enc.sops.yaml /tmp/registry-secrets.yaml > ci/secrets/dockerhub.enc.sops.yaml
```

For deploy with SOPS+KMS in GitHub Actions:
- `GCP_SA_KEY_B64` (base64 of the service account JSON)

## GitHub runner in VM

Runner files are in `var/github-runner/`.

```bash
task runner:init
task runner:up
```

Set token in `var/github-runner/.env` first.

## Validation

```bash
# json sanity check
jq empty monitoring/grafana-dashboard.json
jq empty elk/kibana-dashboard.json

# lint
hadolint Dockerfile
find var/scripts -type f \( -name "*.sh" -o -name "lab-load" -o -name "lab-validate" \) -print0 | xargs -0 shellcheck --severity=warning

# kustomize dry-run
kubectl kustomize k8s/overlays/dev --load-restrictor=LoadRestrictionsNone | kubectl apply --dry-run=client -f -

# endpoint checks
kubectl -n app port-forward svc/observability-app 18080:8080 &
curl -s http://localhost:18080/health
curl -s http://localhost:18080/ready
curl -s http://localhost:18080/request
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:18080/error
curl -s http://localhost:18080/slow
curl -s http://localhost:18080/metrics | head -20
kill %1
```

## Docs

- `var/docs/deployment-guide.md`
- `var/docs/notes.md`
- `var/docs/02-planning.md`
- `var/docs/z-journal.md`

## Notes

- Podinfo used as base image with a minimal shim to enforce endpoint/log contract.
- Metrics via podinfo native Prometheus instrumentation.
- k3s single-node as default local cluster.
- Pipeline logic centralized in `ci/scripts/`.
- Kustomize overlays patch only env-specific values.
