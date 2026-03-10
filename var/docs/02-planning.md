# 02-planning

## Goal

Full compliance artifacts for the lab: endpoints, logging, observability, CI/CD and ELK contracts.

## Decisions

- Custom app in `app/` to enforce strict endpoint contract.
- Mandatory endpoints: `/health`, `/ready`, `/metrics`, `/request`, `/error`, `/slow`.
- Structured logs with required fields: `timestamp`, `level`, `endpoint`, `latency`, `APP_ENV`.
- k3s single-node as default local cluster.
- Canonical pipeline in `ci/pipeline.yaml`, GitHub/GitLab wrappers call `ci/scripts/`.

## Delivery checkpoints

1. Dockerfile: non-root, with `APP_ENV=staging` and configurable `PORT`.
2. Kubernetes manifests at `k8s/`: deployment, service, hpa.
3. Grafana dashboard JSON with required panels and thresholds.
4. ELK files: `elk/logstash.conf`, `elk/kibana-dashboard.json`, `elk/kibana-alert-rule.json`.
5. CI/CD: Lint -> Build -> Push -> Deploy, self-hosted deploy target.
6. README and notes aligned with implementation.
