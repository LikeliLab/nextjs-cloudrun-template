#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"

    echo "Creating service account and Workload Identity Pool for project $PROJECT_ID..."
    
    # Create a dedicated service account for GitHub Actions
    gcloud iam service-accounts create github-actions \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions Service Account" \
    --description="Service account for GitHub Actions deployments"
    
    # Grant necessary roles to the service account
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/run.admin"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.admin"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/clouddeploy.admin"
    
    gcloud iam workload-identity-pools create "nextjs-app-dev" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="Nextjs app pool"

    gcloud iam workload-identity-pools providers create-oidc "nextjs-app-oidc" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="nextjs-app-dev" \
    --display-name="Nextjs app pool" \
    --attribute-mapping="google.subject=assertion.sub" \
    --attribute-condition="assertion.repository_owner=='$GITHUB_OWNER'" \
    --issuer-uri="https://token.actions.githubusercontent.com/"

    # Bind the GitHub Actions service account to the workload identity pool
    gcloud iam service-accounts add-iam-policy-binding "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/nextjs-app-dev/attribute.repository/$GITHUB_OWNER/$GITHUB_REPO"

    # Add Service Account Token Creator role for impersonation
    gcloud iam service-accounts add-iam-policy-binding "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/nextjs-app-dev/attribute.repository/$GITHUB_OWNER/$GITHUB_REPO"


done