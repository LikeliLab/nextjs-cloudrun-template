# After the Cloud Run Admin API is enabled, the Compute Engine default service
# account is automatically created. This script grants the "Service Account 
# User" role to the Compute Engine default service account for each project.


#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    # gcloud run services add-iam-policy-binding $SERVICE_NAME \
    # --member=user:$PRINCIPAL \
    # --role=roles/run.admin

    gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --member="allUsers" \
    --role="roles/run.invoker"

    echo "Granting 'Cloud Run Admin ' role for project $PROJECT_ID..."
    # Lets Cloud Build deploy new services to Cloud Run.

    gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$CLOUD_BUILD_SA \
    --role=roles/run.admin

    echo "Granting 'Storage Admin' role for project $PROJECT_ID..."
    #  Enables reading and writing from Cloud Storage.

    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role=roles/run.builder

    echo "Granting 'Artifact Registry Writer' role for project $PROJECT_ID..."
    # Allows pulling images from and writing to Artifact Registry.

    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role=roles/artifactregistry.writer

    echo "Granting 'Logs Writer' role for project $PROJECT_ID..."
    # Allows log entries to be written to Cloud Logging.

    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role=roles/logging.logWriter

    echo "Granting 'Cloud Build Editor' role for project $PROJECT_ID..."
    # Allows your service account to run builds.

    gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member=serviceAccount:$CLOUD_BUILD_SA \
      --role=roles/cloudbuild.builds.editor

done

echo "Roles Granted!"