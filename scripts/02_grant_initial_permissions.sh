#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

echo "Granting permissions..."
for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  
  # Grant permissions
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/artifactregistry.admin" \
    --condition=None \
    --quiet
    
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/serviceusage.serviceUsageAdmin" \
    --condition=None \
    --quiet
    
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/iam.securityAdmin" \
    --condition=None \
    --quiet
    
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/compute.admin" \
    --condition=None \
    --quiet
    
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/run.admin" \
    --condition=None \
    --quiet
    
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:${YOUR_EMAIL}" \
    --role="roles/iam.serviceAccountAdmin" \
    --condition=None \
    --quiet
    
  echo "✅ Granted necessary roles to ${YOUR_EMAIL} on ${PROJECT_ID}"
done