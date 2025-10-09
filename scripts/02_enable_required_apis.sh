#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  echo "Enabling APIs for ${PROJECT_ID}..."
  
  gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    iamcredentials.googleapis.com \
    compute.googleapis.com \
    iap.googleapis.com \
    secretmanager.googleapis.com \
    --project=${PROJECT_ID}
done