#!/usr/bin/env bash
set -euo pipefail

APP_TAG="${APP_TAG:-app-2.2.0}"
LOADGEN_TAG="${LOADGEN_TAG:-loadgen-1.1.0}"
AWS_REGION="${AWS_REGION:-us-east-1}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="$(terraform -chdir="$HERE" output -raw ecr_repository_url)"
REGISTRY="${REPO_URL%%/*}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

for target in app loadgen; do
  case "$target" in
    app)     tag="$APP_TAG" ;;
    loadgen) tag="$LOADGEN_TAG" ;;
  esac
  echo ">> $target -> $REPO_URL:$tag"
  docker build --platform linux/amd64 \
    --provenance=false --sbom=false \
    ${BASE_IMAGE:+--build-arg BASE_IMAGE="$BASE_IMAGE"} \
    --target "$target" \
    -t "$REPO_URL:$tag" \
    "$HERE"
  docker push "$REPO_URL:$tag"
done
