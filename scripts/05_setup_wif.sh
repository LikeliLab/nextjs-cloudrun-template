#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    echo "Creating Workload Identity Pool for project $PROJECT_ID..."
    
    gcloud iam workload-identity-pools create "nextsjs-app-dev" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="Nextjs app pool"

    gcloud iam workload-identity-pools providers create-oidc "nextjs-app-oidc" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="nextsjs-app-dev" \
    --display-name="Nextjs app pool" \
    --attribute-mapping="google.subject=assertion.sub" \
    --attribute-condition="assertion.repository_owner=='$GITHUB_OWNER'" \
    --issuer-uri="https://token.actions.githubusercontent.com/"

    # gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT \
    # --project="${PROJECT_ID}" \
    # --role="roles/iam.workloadIdentityUser" \
    # --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/nextsjs-app-dev/attribute.repository/$GITHUB_OWNER/$GITHUB_REPO"


done