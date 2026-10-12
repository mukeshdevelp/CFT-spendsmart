#!/usr/bin/env bash
# Pull SpendSmart images from Harbor (machine with Harbor access) and push to ECR.
# Required: docker, aws CLI; HARBOR_USERNAME + HARBOR_PASSWORD (or prior docker login).
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
HARBOR_SERVER="${HARBOR_SERVER:-harbor.ldc.opstree.dev}"
HARBOR_TAG="${HARBOR_TAG:-latest}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-spendsmart}"

if [[ -n "${HARBOR_USERNAME:-}" && -n "${HARBOR_PASSWORD:-}" ]]; then
  echo "$HARBOR_PASSWORD" | docker login "$HARBOR_SERVER" -u "$HARBOR_USERNAME" --password-stdin
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ECR_REGISTRY:-${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com}"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

mirror_one() {
  local component="$1" harbor_image="$2"
  local ecr_repo="${ECR_REPO_PREFIX}/${component}"
  local src="${harbor_image}:${HARBOR_TAG}"
  local dst="${ECR_REGISTRY}/${ecr_repo}:${IMAGE_TAG}"

  aws ecr describe-repositories --repository-names "$ecr_repo" --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$ecr_repo" --region "$AWS_REGION" >/dev/null

  echo "=== ${src} -> ${dst} ==="
  docker pull "$src"
  docker tag "$src" "$dst"
  docker push "$dst"
  if [[ "$IMAGE_TAG" != "latest" ]]; then
    local latest_dst="${ECR_REGISTRY}/${ecr_repo}:latest"
    docker tag "$src" "$latest_dst"
    docker push "$latest_dst"
  fi
}

mirror_one backend "${HARBOR_SERVER}/coe/uniteconpro-backend-prod"
mirror_one frontend "${HARBOR_SERVER}/coe/uniteconpro-frontend-prod"
mirror_one engine "${HARBOR_SERVER}/coe/uniteconpro-engine-dev"

echo "Done. ECR images (tag ${IMAGE_TAG}):"
echo "  ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/backend:${IMAGE_TAG}"
echo "  ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/frontend:${IMAGE_TAG}"
echo "  ${ECR_REGISTRY}/${ECR_REPO_PREFIX}/engine:${IMAGE_TAG}"
