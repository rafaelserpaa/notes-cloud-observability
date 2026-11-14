#!/usr/bin/env bash
# Copia as imagens do backend de observabilidade (Docker Hub) para os
# repositórios lab-obs/* no ECR. A EC2 de backend fica numa subnet privada sem
# NAT e só consegue puxar imagens do ECR (pelos VPC Endpoints).
#
#   terraform apply -target=module.obs_image_repos
#   scripts/mirror-images.sh
#
# A cópia é registry -> registry (buildx imagetools): leva o índice multi-arch
# inteiro, sem baixar as camadas para a máquina local. Tags que já existem no
# ECR são puladas (os repositórios são IMMUTABLE).
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

MIRROR_JSON="$(terraform -chdir="$HERE" output -json obs_image_mirror)"
[ "$(jq 'length' <<<"$MIRROR_JSON")" -gt 0 ] || { echo "obs_image_mirror vazio (enable_observability = false?)"; exit 1; }

REGISTRY="$(jq -r 'first(.[]).target | split("/")[0]' <<<"$MIRROR_JSON")"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

jq -r 'to_entries[] | "\(.value.source) \(.value.target)"' <<<"$MIRROR_JSON" |
while read -r source target; do
  repo="${target#*/}"; repo="${repo%:*}"
  tag="${target##*:}"
  if aws ecr describe-images --region "$AWS_REGION" --repository-name "$repo" \
       --image-ids imageTag="$tag" </dev/null >/dev/null 2>&1; then
    echo "== $repo:$tag já existe, pulando"
    continue
  fi
  echo ">> $source -> $target"
  docker buildx imagetools create --tag "$target" "$source" </dev/null
done
