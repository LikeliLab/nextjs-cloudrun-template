#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in dev stage prod; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"
    WORKLOAD_IDENTITY_POOL_NAME="github-actions-pool-$ENV"

    # Create a workload identity pool
    gcloud iam workload-identity-pools create $WORKLOAD_IDENTITY_POOL_NAME \
        --location="global" \
        --description="The pool to authenticate GitHub actions." \
        --display-name="GitHub Actions Pool - $ENV" \
        --project="$PROJECT_ID"

    # Create a workload identity provider within the pool
    gcloud iam workload-identity-pools providers create-oidc GitHub-actions-oidc \
        --workload-identity-pool="github-actions-pool-$ENV" \
        --issuer-uri="https://token.actions.GitHubusercontent.com/" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.branch=assertion.sub.extract('/heads/{branch}/')" \
        --location=global \
        --attribute-condition="assertion.repository_owner=='$GITHUB_OWNER' && assertion.repository=='$GITHUB_REPO' && assertion.branch=='$ENV'" \
        --project="$PROJECT_ID"

    # Create a service account for each repository and assign them appropriate IAM permissions
    gcloud iam service-accounts create nextjs-app-sa-dev --display-name="Example Application Service Account - dev" --description="manages the application resources"
    gcloud iam service-accounts create networking-sa-dev --display-name="Networking Service Account - dev" --description="manages the networking resources"

    # Add IAM bindings for the workload pool 
    PROJECT_NUMBER = gcloud projects describe $PROJECT_ID --format="value(projectNumber)"

    gcloud iam service-accounts add-iam-policy-binding networking-sa-dev@nextjs-cloudrun-template-dev.iam.gserviceaccount.com --role="roles/iam.workloadIdentityUser" --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool-dev/attribute.repository/michaelellis003/nextjs-cloudrun-template"
    gcloud iam service-accounts add-iam-policy-binding nextjs-app-sa-dev@nextjs-cloudrun-template-dev.iam.gserviceaccount.com --role="roles/iam.workloadIdentityUser" --member="principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool-dev/subject/repo:michaelellis003/nextjs-cloudrun-template:ref:refs/heads/main"

    # 5. Update the GitHub Actions workflow to use the workload identity pool to authenticate to Google Cloud.