#!/usr/bin/env bash
# Builda e envia ao ECR as duas imagens do lab de observabilidade a partir do
# Dockerfile multistage da raiz (base: rafaelserpa/notas-da-nuvem).
#
#   scripts/build-push.sh
#
# Variáveis opcionais: APP_TAG, LOADGEN_TAG, BASE_IMAGE, AWS_REGION.
set -euo pipefail

APP_TAG="${APP_TAG:-app-2.2.0}"                 # mesmo valor de var.otel_image_tag
LOADGEN_TAG="${LOADGEN_TAG:-loadgen-1.1.0}"     # mesmo valor de var.loadgen_image_tag
BASE_IMAGE="${BASE_IMAGE:-rafaelserpa/notas-da-nuvem:1.0.0}"
AWS_REGION="${AWS_REGION:-us-east-1}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="$(terraform -chdir="$HERE" output -raw ecr_repository_url)"
REGISTRY="${REPO_URL%%/*}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# Fargate roda em X86_64. O segundo build reaproveita do cache as camadas base/otel.
# --provenance/--sbom=false: sem eles o buildx publica um index com um manifesto de
# attestation, e o ECR (IMMUTABLE) chega a amarrar a tag nesse manifesto, sem imagem.
for target in app loadgen; do
  case "$target" in
    app)     tag="$APP_TAG" ;;
    loadgen) tag="$LOADGEN_TAG" ;;
  esac
  echo ">> $target -> $REPO_URL:$tag"
  docker build --platform linux/amd64 \
    --provenance=false --sbom=false \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --target "$target" \
    -t "$REPO_URL:$tag" \
    "$HERE"
  docker push "$REPO_URL:$tag"
done
