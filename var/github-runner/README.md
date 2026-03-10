# GitHub Runner (docker compose)

Simple self-hosted runner for this VM.

## Quick setup

```bash
cd /home/vagrant/observability-lab
task runner:init
```

Edit `var/github-runner/.env`:

- set `REPO_URL`
- set `RUNNER_TOKEN`

Then start:

```bash
task runner:up
task runner:status
task runner:logs
```

Stop:

```bash
task runner:down
```

Notes:

- Runner has docker socket and k3s kubeconfig mounted.
- It can run build/deploy jobs directly against this VM cluster.
