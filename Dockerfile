# syntax=docker/dockerfile:1
#
# Imagens do lab de observabilidade a partir da imagem pública da aplicação.
# Um único Dockerfile, dois targets:
#
#   app      -> Notas da Nuvem com auto-instrumentação OpenTelemetry (tag app-2.2.0)
#   loadgen  -> gerador de tráfego instrumentado                   (tag loadgen-1.1.0)
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
# Versões fixas: os nomes de métricas e atributos dependem da versão da
# instrumentação, e as regras de alerta/dashboard contam com eles.
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

# ---------------------------------------------------------------- app
# Mesmo app da imagem base, embrulhado pelo opentelemetry-instrument.
# Configuração (endpoint, protocolo, nome do serviço) vem das variáveis OTEL_* da task.
#
# Um worker com threads, e não vários workers: o SDK é inicializado antes do fork,
# então workers irmãos exportariam métricas cumulativas com o MESMO recurso
# (mesmo service.instance.id). As séries se misturariam no Prometheus e o rate()
# veria "resets" falsos. Com um processo por task, cada task = uma instância OTel.
FROM otel AS app
EXPOSE 8080
CMD ["opentelemetry-instrument", \
     "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", \
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
