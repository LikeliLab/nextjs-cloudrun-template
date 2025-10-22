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

    echo "Creating Artifact Registry repository for project $PROJECT_ID..."

    # Check if repository already exists
    if gcloud artifacts repositories describe $ARTIFACT_REPOSITORY \
        --location=$ARTIFACT_LOCATION \
        --project=$PROJECT_ID &>/dev/null; then
        echo "✅ Artifact Registry repository '$ARTIFACT_REPOSITORY' already exists in $PROJECT_ID"
    else
        if gcloud artifacts repositories create $ARTIFACT_REPOSITORY \
          --repository-format=docker \
          --location=$ARTIFACT_LOCATION \
          --description="Docker repository for $PROJECT_ID" \
          --project $PROJECT_ID; then
            echo "✅ Artifact Registry repository created successfully for $PROJECT_ID"
        else
            echo "❌ Failed to create Artifact Registry repository for $PROJECT_ID" >&2
        fi
    fi
    echo "---"
done

echo "🎉 Artifact Registry setup completed!"