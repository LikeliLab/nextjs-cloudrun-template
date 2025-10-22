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

    # Check if project exists before proceeding
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo "❌ Project $PROJECT_ID does not exist. Please run 01_create_projects.sh first."
        continue
    fi

    echo "Enabling APIs for project $PROJECT_ID..."

    if gcloud config set project "$PROJECT_ID"; then
        if gcloud services enable \
            run.googleapis.com \
            cloudbuild.googleapis.com \
            artifactregistry.googleapis.com \
            cloudresourcemanager.googleapis.com \
            clouddeploy.googleapis.com \
            --project $PROJECT_ID; then
            echo "✅ APIs enabled successfully for $PROJECT_ID"
        else
            echo "❌ Failed to enable some APIs for $PROJECT_ID" >&2
        fi
    else
        echo "❌ Failed to set project context for $PROJECT_ID" >&2
    fi
    echo "---"
done

# Check if WIF project exists before proceeding
if ! gcloud projects describe "$WIF_PROJECT_ID" &>/dev/null; then
    echo "❌ WIF project $WIF_PROJECT_ID does not exist. Please run 01_create_projects.sh first."
    exit 1
fi

echo "Enabling APIs for WIF project $WIF_PROJECT_ID..."
if gcloud config set project "$WIF_PROJECT_ID"; then
    if gcloud services enable \
        iamcredentials.googleapis.com \
        --project $WIF_PROJECT_ID; then
        echo "✅ APIs enabled successfully for $WIF_PROJECT_ID"
    else
        echo "❌ Failed to enable APIs for $WIF_PROJECT_ID" >&2
    fi
else
    echo "❌ Failed to set project context for $WIF_PROJECT_ID" >&2
fi

echo "🎉 API enablement process completed!"