#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    echo "========================================="
    echo "Creating service accounts for project: $PROJECT_ID"
    echo "========================================="

    echo "Create GitHub Actions service account..."
    gcloud iam service-accounts create $GH_SA_NAME \
    --project "$PROJECT_ID" \
    --description="Github actions identity for Cloud Run app" \
    --display-name="Github actions Service Account"

    echo "Create Cloud Run Runtime service account..."
    gcloud iam service-accounts create $RUNTIME_SA_NAME \
    --project "$PROJECT_ID" \
    --description="Runtime identity for Cloud Run app" \
    --display-name="Cloud Run App Service Account"

    echo "Grant roles for GitHub Actions service account..."
    GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    RUNTIME_SA="$RUNTIME_SA_NAME@${PROJECT_ID}.iam.gserviceaccount.com"

    echo "Grant Cloud Run Developer at project level for GitHub Actions service account..."
    # 1. Cloud Run Developer
    gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${GH_SA}" \
    --role="roles/run.developer"

    echo "Grant Artifact Registry Writer at repo level for GitHub Actions service account..."
    # 2. Artifact Registry Reader (repository-level, not project-level)
    gcloud artifacts repositories add-iam-policy-binding $ARTIFACT_REPOSITORY \
    --location=$ARTIFACT_LOCATION \
    --member="serviceAccount:${GH_SA}" \
    --role="roles/artifactregistry.writer"

    echo "Grant Service Account User for Cloud Run runtime service account for GitHub Actions service account..."
    # 3. Service Account User (on specific runtime SA only, not project-level)
   gcloud iam service-accounts add-iam-policy-binding $RUNTIME_SA \
    --member="serviceAccount:${GH_SA}" \
    --role="roles/iam.serviceAccountUser"
done