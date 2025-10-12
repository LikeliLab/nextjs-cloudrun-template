#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    echo "Creating Artifact Registry repository for project $PROJECT_ID..."

    gcloud artifacts repositories create $ARTIFACT_REPOSITORY \
      --repository-format=docker \
      --location=$ARTIFACT_LOCATION \
      --description="Docker repository for $PROJECT_ID" \
      --project $PROJECT_ID
done