# syntax=docker/dockerfile:1

ARG BASE_IMAGE=rafaelserpa/notas-da-nuvem:1.0.0

FROM ${BASE_IMAGE} AS base

FROM base AS otel
ARG OTEL_SDK_VERSION=1.45.2
ARG OTEL_CONTRIB_VERSION=0.66b2
USER root
RUN pip install --no-cache-dir \
      requests \
      "opentelemetry-distro==${OTEL_CONTRIB_VERSION}" \
      "opentelemetry-exporter-otlp==${OTEL_SDK_VERSION}" \
 && opentelemetry-bootstrap -a install \
 && pip check
USER appuser

FROM otel AS app
EXPOSE 8080
CMD ["opentelemetry-instrument", \
     "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", \
     "--access-logfile", "-", "app:app"]

FROM otel AS loadgen
USER root
RUN rm -rf /app/app.py /app/templates
COPY --chown=root:root --chmod=644 loadgen/loadgen.py /app/loadgen.py
USER appuser
HEALTHCHECK NONE
CMD ["opentelemetry-instrument", "python", "loadgen.py"]
