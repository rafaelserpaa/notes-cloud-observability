#!/usr/bin/env bash
# Build e push das duas imagens da observabilidade (Passos 3 e Fase 4).
# Uso, na raiz deste projeto, depois de `terraform apply -target=module.ecr`:
#   scripts/build-push-otel.sh /caminho/para/aula-06-cloud-cyber-app
set -euo pipefail

APP_DIR="${1:?informe o caminho do repositório da aplicação (aula-06-cloud-cyber-app)}"
OTEL_TAG="${OTEL_TAG:-2.0.0-otel}"
LOADGEN_TAG="${LOADGEN_TAG:-1.0.0-loadgen}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="$(terraform -chdir="$HERE" output -raw ecr_repository_url)"
REGISTRY="${REPO_URL%%/*}"

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REGISTRY"

# Aplicação: o Dockerfile.otel vai junto do código, que não muda.
cp "$HERE/otel/Dockerfile.otel" "$APP_DIR/Dockerfile.otel"
docker build --platform linux/amd64 -f "$APP_DIR/Dockerfile.otel" -t "$REPO_URL:$OTEL_TAG" "$APP_DIR"
docker push "$REPO_URL:$OTEL_TAG"

# Loadgen
docker build --platform linux/amd64 -f "$HERE/loadgen/Dockerfile.loadgen" -t "$REPO_URL:$LOADGEN_TAG" "$HERE/loadgen"
docker push "$REPO_URL:$LOADGEN_TAG"
