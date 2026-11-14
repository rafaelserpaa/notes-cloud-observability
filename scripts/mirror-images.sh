#!/usr/bin/env bash
# Copia as imagens do backend de observabilidade (Docker Hub) para os
# repositórios lab-obs/* no ECR. A EC2 de backend fica numa subnet privada sem
# NAT e só consegue puxar imagens do ECR (pelos VPC Endpoints).
#
#   terraform apply -target=module.obs_image_repos
#   scripts/mirror-images.sh
#
# Só a variante linux/amd64 é enviada, como imagem de plataforma única (a EC2 é
# x86_64). Não use "docker buildx imagetools create" aqui: ele envia cada manifesto
# de plataforma com a própria tag, e num repositório IMMUTABLE o primeiro (ex.:
# ppc64le) fica preso na tag e o resto falha com 400.
#
# Tags que já existem são puladas se forem linux/amd64; se forem de outra
# arquitetura (sobra de uma tentativa anterior), o script para e mostra como apagar.
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
    arch="$(docker buildx imagetools inspect "$target" --format '{{json .Image}}' </dev/null 2>/dev/null \
      | jq -r 'if has("architecture") then .architecture else (.["linux/amd64"] | if . then "amd64" else "?" end) end')"
    if [ "$arch" = "amd64" ]; then
      echo "== $repo:$tag já existe (linux/amd64), pulando"
      continue
    fi
    echo "!! $repo:$tag existe mas não é linux/amd64 (arch=$arch). Apague e rode de novo:"
    echo "   aws ecr batch-delete-image --region $AWS_REGION --repository-name $repo --image-ids imageTag=$tag"
    exit 1
  fi
  echo ">> $source -> $target (linux/amd64)"
  docker pull --quiet --platform linux/amd64 "$source" </dev/null
  docker tag "$source" "$target"
  docker push --quiet --platform linux/amd64 "$target" </dev/null
done
