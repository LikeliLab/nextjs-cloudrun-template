#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

echo "Granting permissions..."

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  
  # Grant permissions (adding --quiet suppresses "already exists" warnings)
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/artifactregistry.admin" \
    --quiet
  
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/serviceusage.serviceUsageAdmin" \
    --quiet
  
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/iam.securityAdmin" \
    --quiet
  
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/compute.admin" \
    --quiet
  
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/run.admin" \
    --quiet
  
  echo "✅ Granted necessary roles to ${YOUR_EMAIL} on ${PROJECT_ID}"
done

echo ""
echo "Creating artifact repositories..."

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  
  # Check if repository exists
  if gcloud artifacts repositories describe nextjs-apps \
    --location=us-central1 \
    --project=${PROJECT_ID} &>/dev/null; then
    echo "⏭️  Repository 'nextjs-apps' already exists in ${PROJECT_ID}"
  else
    gcloud artifacts repositories create nextjs-apps \
      --repository-format=docker \
      --location=us-central1 \
      --description="Next.js containers for ${ENV}" \
      --project=${PROJECT_ID}
    echo "✅ Created repository 'nextjs-apps' in ${PROJECT_ID}"
  fi
done

echo ""
echo "✅ Setup complete!"