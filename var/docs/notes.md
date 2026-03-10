# Notes

## App

- Single container (`observability-app`) on port 8080.
- Endpoints: `/health`, `/ready`, `/metrics`, `/request`, `/error`, `/slow`.

## Logging

- App emits structured JSON to stdout with: `timestamp`, `level`, `endpoint`, `latency`, `APP_ENV`.
- Filebeat forwards pod logs to Logstash.
- Logstash parses and normalizes, indexes as `app-logs-{environment}-{date}`.

## Metrics

- Podinfo native Prometheus instrumentation.
- Grafana panels: CPU, latency histogram, request counter, error rate, P95.

## CI/CD

- Canonical pipeline in `ci/pipeline.yaml`.
- GitHub/GitLab wrappers call `ci/scripts/`.
- Deploy targets self-hosted runner.

## Alerting

- Kibana rule `observability-errors-20-in-5m`: >= 20 ERROR logs in 5 minutes.
- Action: server-log connector.
- Throttle: 5 minutes.
