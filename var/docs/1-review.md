# Lab requirements

1. Kubernetes:
    1. MANDATORY: manifests, probes, resources, HPA
    2. Cluster: k3s single-node
    3. Must run fully local
    4. kubectl must work
    5. Easy to recreate
    6. Helm available in env

2. App:
    1. Deployment with 2 replicas
    2. Service: correct exposition
    3. ConfigMap: APP_ENV configured
    4. HPA v2: autoscaling based on CPU > 70% and memory
    5. Probes: liveness and readiness
    6. Mandatory manifests: deployment.yaml, service.yaml, hpa.yaml
    7. Good manifest organization
    8. Resources, probes, labels
    9. ConfigMap for configuration management
    10. Prometheus annotations required
    11. Mandatory endpoints: /health, /ready, /metrics
    12. Structured logs required
    13. Mandatory log fields: timestamp, level, endpoint, latency
    14. Traffic endpoints: /request, /error, /slow
    15. APP_ENV must appear in logs

3. Application:
    1. Keycloak is a good option
    2. DIY app is optional (podinfo recomended)

4. Docker:
    1. MANDATORY: Dockerfile, security, optimization
    2. Security: minimal best practices in Dockerfile
    3. Official base images, non-root user
    4. APP_ENV=staging via environment variable
    5. PORT via ENV and ARG
    6. Document basic commands (Taskfiles)
    7. Optimization: minimal image size, multi-stage if needed
    8. Follow Docker conventions
    9. Dockerfile must pass hadolint
    10. Document: docker build, docker run

5. ELK and Grafana deployed via Helm:
    1. Use Taskfile for all operations
    2. Include YAML values files
    3. ELK components: Elasticsearch, Logstash, Kibana
    4. Collect layer: Filebeat or FluentBit DaemonSet

6. CI/CD pipeline:
    1. Automate image build
    2. Automate k8s deployment

7. Validate observability:
    1. Validate Grafana
    2. Validate ELK
    3. Validate metrics scraping
    4. Validate logs arriving in Elasticsearch
    5. Validate parsed fields (timestamp, level, endpoint, latency)
    6. Validate HPA scaling and probes
    7. Validate pipeline deploying automatically

8. Dashboards:
    1. Best SRE metrics visible

9. Observability:
    1. MANDATORY: metrics, dashboards, collection
    2. /metrics using Prometheus client library
    3. Deployment annotations for auto-scraping
    4. Grafana dashboard with essential metrics
    5. CPU usage: gauge per pod
    6. Latency: histogram, average latency per request
    7. Request counter: total requests
    8. Error rate per minute
    9. Dashboard: overview with 4-6 panels
    10. Time range configurable
    11. Visual thresholds on panels
    12. Dashboard exported as JSON
    13. Annotations: prometheus.io/scrape=true, prometheus.io/port=8080, prometheus.io/path=/metrics

10. CI/CD:
    1. MANDATORY: automation, organization, efficiency
    2. Platform: GitHub Actions or GitLab CI
    3. Stages: Lint -> Build -> Push -> Deploy
    4. Deploy target: self-hosted k8s cluster
    5. Taskfiles/shell scripts so any platform works
    6. Lint: hadolint + shellcheck
    7. Build: docker build
    8. Push: Docker Hub / GCR / ECR
    9. Deploy: kubectl or helm to self-hosted k8s
    10. Clear logs and organized steps

11. ELK:
    1. MANDATORY: pipeline, parsing, dashboard, alerts
    2. Full ELK stack: collect, process, visualize, alert
    3. DaemonSet: Filebeat or FluentBit
    4. Collect stdout from pods
    5. Index pattern: app-logs-{environment}-{date}
    6. Logstash: functional logstash.conf
    7. Input: beats or stdin
    8. Filter: grok/dissect to extract fields
    9. Output: Elasticsearch with template
    10. Mandatory fields: level, endpoint, latency, timestamp
    11. Example filter: grok{ match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:endpoint} latency=%{NUMBER:latency}ms" }}
    12. Kibana dashboard exported as kibana-dashboard.json
    13. Required visualizations:
        1. Log volume by level: pie chart
        2. Top endpoints: data table
        3. Errors over time: line chart
        4. Latency histogram
        5. Log explorer: discover view
    14. Kibana alert:
        1. Trigger: >= 20 errors in last 5 minutes
        2. Action: notification configured
        3. Throttle: avoid spam

12. Final structure:

    ```text
    /repo:
      - README.md
      - Dockerfile
      - /app/
      - /k8s/
          - deployment.yaml
          - service.yaml
          - hpa.yaml
      - /monitoring/
          - grafana-dashboard.json
      - /ci/
          - pipeline.yaml
      - /var/docs/
          - notes.md
          - 02-planning.md
          - z-journal.md
      - /elk/
          - logstash.conf
          - kibana-dashboard.json
    ```

13. Mandatory deliverables:
    1. README.md - complete docs with instructions
    2. Dockerfile - secure and optimized
    3. K8s manifests - deployment, service, HPA
    4. Grafana dashboard - essential metrics
    5. CI/CD pipeline - full automation
    6. ELK stack - logs + dashboard + alerts

# Key points

- Containerization: good and secure image
- Kubernetes: deploy to cluster
- Observability: metrics and dashboards
- CI/CD: automate build, test, deploy
- ELK: collect, process, visualize logs
- Docs: organization and SRE best practices

# Success criteria

- Document every technical decision
- Explain non-obvious configs
- Functionality over perfection
- Validate each component before delivery
