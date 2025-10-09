#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

echo "Creating artifact repositories..."

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  
  # Check if repository exists
  if gcloud artifacts repositories describe ${ARTIFACT_REGISTRY_NAME} \
    --location=us-central1 \
    --project=${PROJECT_ID} &>/dev/null; then
    echo "⏭️  Repository ${ARTIFACT_REGISTRY_NAME} already exists in ${PROJECT_ID}"
  else
    gcloud artifacts repositories create ${ARTIFACT_REGISTRY_NAME} \
      --repository-format=docker \
      --location=us-central1 \
      --description="Next.js containers for ${ENV}" \
      --project=${PROJECT_ID}
    echo "✅ Created repository ${ARTIFACT_REGISTRY_NAME} in ${PROJECT_ID}"
  fi
done

echo ""
echo "✅ Setup complete!"