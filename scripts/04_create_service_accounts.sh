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
      --display-name="Github actions Service Account" 2>/dev/null || echo "✓ Already exists"

    echo "Create Cloud Run Runtime service account..."
    gcloud iam service-accounts create $RUNTIME_SA_NAME \
      --project "$PROJECT_ID" \
      --description="Runtime identity for Cloud Run app" \
      --display-name="Cloud Run App Service Account" 2>/dev/null || echo "✓ Already exists"

    echo ""
    echo "Grant roles for GitHub Actions service account..."
    GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    RUNTIME_SA="${RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    echo "  → Cloud Run Developer (project level)..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${GH_SA}" \
      --role="roles/run.developer" \
      --condition=None

    echo "  → Artifact Registry Writer (repository level)..."
    
    # Check if Artifact Registry repo exists
    if gcloud artifacts repositories describe $ARTIFACT_REPOSITORY \
      --location=$ARTIFACT_LOCATION \
      --project=$PROJECT_ID &>/dev/null; then
      
      # Grant at repository level (least privilege)
      gcloud artifacts repositories add-iam-policy-binding $ARTIFACT_REPOSITORY \
        --location=$ARTIFACT_LOCATION \
        --project=$PROJECT_ID \
        --member="serviceAccount:${GH_SA}" \
        --role="roles/artifactregistry.writer"
      
      echo "     ✅ Granted at repository level"
    else
      echo "     ❌ ERROR: Artifact Registry repository '$ARTIFACT_REPOSITORY' does not exist!"
      echo "     Please run 03_create_artifact_registry_repo.sh first"
      exit 1
    fi

    echo "  → Service Account User (on runtime SA only)..."
    gcloud iam service-accounts add-iam-policy-binding $RUNTIME_SA \
      --project=$PROJECT_ID \
      --member="serviceAccount:${GH_SA}" \
      --role="roles/iam.serviceAccountUser"

    echo ""
    echo "✅ Service accounts configured for $PROJECT_ID"
    echo ""
done

echo "🎉 All service accounts created and configured!"