#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    # Check if project exists before proceeding
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo "❌ Project $PROJECT_ID does not exist. Please run 01_create_projects.sh first."
        continue
    fi

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
    if gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:${GH_SA}" \
      --role="roles/run.developer" \
      --condition=None 2>/dev/null; then
        echo "     ✅ Cloud Run Developer role granted"
    else
        echo "     ⚠️ Cloud Run Developer role may already be granted or failed to grant"
    fi

    echo "  → Artifact Registry Writer (repository level)..."
    
    # Check if Artifact Registry repo exists
    if gcloud artifacts repositories describe $ARTIFACT_REPOSITORY \
      --location=$ARTIFACT_LOCATION \
      --project=$PROJECT_ID &>/dev/null; then
      
      # Grant at repository level (least privilege)
      if gcloud artifacts repositories add-iam-policy-binding $ARTIFACT_REPOSITORY \
        --location=$ARTIFACT_LOCATION \
        --project=$PROJECT_ID \
        --member="serviceAccount:${GH_SA}" \
        --role="roles/artifactregistry.writer" 2>/dev/null; then
        echo "     ✅ Artifact Registry Writer role granted"
      else
        echo "     ⚠️ Artifact Registry Writer role may already be granted or failed to grant"
      fi
    else
      echo "     ❌ ERROR: Artifact Registry repository '$ARTIFACT_REPOSITORY' does not exist!"
      echo "     Please run 03_create_artifact_registry_repo.sh first"
      continue
    fi

    echo "  → Service Account User (on runtime SA only)..."
    if gcloud iam service-accounts add-iam-policy-binding $RUNTIME_SA \
      --project=$PROJECT_ID \
      --member="serviceAccount:${GH_SA}" \
      --role="roles/iam.serviceAccountUser" 2>/dev/null; then
        echo "     ✅ Service Account User role granted"
    else
        echo "     ⚠️ Service Account User role may already be granted or failed to grant"
    fi

    echo ""
    echo "✅ Service accounts configured for $PROJECT_ID"
    echo ""
done

echo "🎉 All service accounts created and configured!"