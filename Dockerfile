# syntax=docker/dockerfile:1
#
# Imagens do lab de observabilidade a partir da imagem pública da aplicação.
# Um único Dockerfile, dois targets:
#
#   app      -> Notas da Nuvem com auto-instrumentação OpenTelemetry (tag app-2.1.0)
#   loadgen  -> gerador de tráfego instrumentado                   (tag loadgen-1.0.0)
#
# Build e push dos dois de uma vez: scripts/build-push.sh

ARG BASE_IMAGE=rafaelserpa/notas-da-nuvem:1.0.0

# ---------------------------------------------------------------- base
# Python 3.13 com venv em /opt/venv (já no PATH), app em /app, usuário appuser (10001).
FROM ${BASE_IMAGE} AS base

# ---------------------------------------------------------------- otel
# Camada comum: SDK + exporter OTLP + instrumentações. O "requests" entra antes do
# opentelemetry-bootstrap para que a instrumentação dele (usada pelo loadgen) também
# seja instalada; Flask e psycopg2 já vêm da imagem base.
FROM base AS otel
USER root
RUN pip install --no-cache-dir \
      requests \
      opentelemetry-distro \
      opentelemetry-exporter-otlp \
 && opentelemetry-bootstrap -a install \
 && pip check
USER appuser

# ---------------------------------------------------------------- app
# Mesmo comando da imagem base, só que embrulhado pelo opentelemetry-instrument.
# Configuração (endpoint, protocolo, nome do serviço) vem das variáveis OTEL_* da task.
FROM otel AS app
EXPOSE 8080
CMD ["opentelemetry-instrument", \
     "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--preload", \
     "--access-logfile", "-", "app:app"]

# ---------------------------------------------------------------- loadgen
FROM otel AS loadgen
# O app da imagem base não é usado aqui; sai para não confundir.
USER root
RUN rm -rf /app/app.py /app/templates
COPY --chown=root:root --chmod=644 loadgen/loadgen.py /app/loadgen.py
USER appuser
# O HEALTHCHECK herdado testa :8080/health, que não existe no loadgen.
HEALTHCHECK NONE
CMD ["opentelemetry-instrument", "python", "loadgen.py"]
