#!/bin/bash

# This script enables required Google Cloud APIs for the Next.js Cloud Run project.
# It enables the following APIs for each environment defined in PROJECT_ENVS:
# - Cloud Run API (run.googleapis.com)
# - Cloud Build API (cloudbuild.googleapis.com) 
# - Artifact Registry API (artifactregistry.googleapis.com)
# - Cloud Resource Manager API (cloudresourcemanager.googleapis.com)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    echo "Enabling APIs for project $PROJECT_ID..."

    gcloud config set project "$PROJECT_ID"
    gcloud services enable \
        run.googleapis.com \
        cloudbuild.googleapis.com \
        artifactregistry.googleapis.com \
        cloudresourcemanager.googleapis.com \
        clouddeploy.googleapis.com \
        iamcredentials.googleapis.com \
        --project $PROJECT_ID
done

echo "APIs Enabled!"