# adds python3 and the shim on top of podinfo image

FROM ghcr.io/stefanprodan/podinfo:6.7.1

USER root
WORKDIR /home/app

# hadolint ignore=DL3018
RUN apk add --no-cache python3

ARG PORT=8080
ARG PODINFO_PORT=9898
ENV PORT=${PORT}
ENV PODINFO_PORT=${PODINFO_PORT}
ENV APP_ENV=staging
ENV SLOW_SECONDS=2
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY app/podinfo_shim.py /home/app/podinfo_shim.py
COPY app/entrypoint.sh /home/app/entrypoint.sh

RUN chmod +x /home/app/entrypoint.sh && chown -R app:app /home/app

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["sh", "-c", "wget -q -O /dev/null http://127.0.0.1:${PORT}/health"]

ENTRYPOINT ["/home/app/entrypoint.sh"]
