# syntax=docker/dockerfile:1

ARG BASE_IMAGE=rafaelserpa/notas-da-nuvem:1.0.0@sha256:d7f1e84bfadeb1b65fcbe58671ed200584a28d2294bc4b12070de28785a24fc8

FROM ${BASE_IMAGE} AS base

FROM base AS otel
USER root
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
COPY --chmod=644 requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && opentelemetry-bootstrap -a install \
 && pip check \
 && rm -f /tmp/requirements.txt
COPY --chmod=644 app.py /app/app.py
USER appuser

FROM otel AS test
USER root
COPY --chmod=644 requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements-dev.txt && rm -f /tmp/requirements-dev.txt
COPY --chown=root:root --chmod=755 tests/ /tests/
USER appuser
WORKDIR /app
HEALTHCHECK NONE
CMD ["python", "-m", "pytest", "/tests", "-p", "no:cacheprovider", "-v", \
     "--junitxml=/reports/junit-observabilidade.xml"]

FROM otel AS runtime
USER root
RUN python -m pip uninstall -y -q pip \
 && /usr/local/bin/python -m pip uninstall -y -q pip \
 && rm -rf /usr/local/lib/python3*/ensurepip
USER appuser

FROM runtime AS app
EXPOSE 8080
CMD ["opentelemetry-instrument", \
     "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", \
     "--access-logfile", "-", "app:app"]

FROM runtime AS loadgen
USER root
RUN rm -rf /app/app.py /app/templates
COPY --chown=root:root --chmod=644 loadgen/loadgen.py /app/loadgen.py
USER appuser
HEALTHCHECK NONE
CMD ["opentelemetry-instrument", "python", "loadgen.py"]
