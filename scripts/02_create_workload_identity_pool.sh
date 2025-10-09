#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

ENV='dev'
PROJECT_ID="${PROJECT_PREFIX}-$ENV"
WORKLOAD_IDENTITY_POOL_NAME="github-actions-pool-$ENV"

echo "Setting up workload identity and service accounts for project: $PROJECT_ID"

# Check and create workload identity pool
if gcloud iam workload-identity-pools describe $WORKLOAD_IDENTITY_POOL_NAME \
  --location="global" \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Workload identity pool '$WORKLOAD_IDENTITY_POOL_NAME' already exists"
else
  echo "Creating workload identity pool '$WORKLOAD_IDENTITY_POOL_NAME'..."
  gcloud iam workload-identity-pools create $WORKLOAD_IDENTITY_POOL_NAME \
    --location="global" \
    --description="The pool to authenticate GitHub actions." \
    --display-name="GitHub Actions Pool - $ENV" \
    --project="$PROJECT_ID"
  echo "✓ Workload identity pool created"
fi

# Check and create workload identity provider
if gcloud iam workload-identity-pools providers describe github-actions-oidc \
  --workload-identity-pool="$WORKLOAD_IDENTITY_POOL_NAME" \
  --location=global \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Workload identity provider 'github-actions-oidc' already exists"
else
  echo "Creating workload identity provider 'github-actions-oidc'..."
  gcloud iam workload-identity-pools providers create-oidc github-actions-oidc \
    --workload-identity-pool="$WORKLOAD_IDENTITY_POOL_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com/" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.branch=assertion.sub.extract('/heads/{branch}/')" \
    --location=global \
    --attribute-condition="assertion.repository_owner=='$GITHUB_OWNER' && assertion.repository=='$GITHUB_REPO' && assertion.branch=='$ENV'" \
    --project="$PROJECT_ID"
  echo "✓ Workload identity provider created"
fi

# Check and create application service account
APP_SA="nextjs-app-sa-$ENV"
if gcloud iam service-accounts describe $APP_SA@$PROJECT_ID.iam.gserviceaccount.com \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Service account '$APP_SA' already exists"
else
  echo "Creating service account '$APP_SA'..."
  gcloud iam service-accounts create $APP_SA \
    --display-name="Example Application Service Account - $ENV" \
    --description="manages the application resources" \
    --project="$PROJECT_ID"
  echo "✓ Service account '$APP_SA' created"
fi

# Check and create networking service account
NET_SA="networking-sa-$ENV"
if gcloud iam service-accounts describe $NET_SA@$PROJECT_ID.iam.gserviceaccount.com \
  --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Service account '$NET_SA' already exists"
else
  echo "Creating service account '$NET_SA'..."
  gcloud iam service-accounts create $NET_SA \
    --display-name="Networking Service Account - $ENV" \
    --description="manages the networking resources" \
    --project="$PROJECT_ID"
  echo "✓ Service account '$NET_SA' created"
fi

# Function to check if IAM policy binding exists
check_iam_binding() {
  local member=$1
  local role=$2
  local resource_type=$3
  local resource=$4
  
  if [ "$resource_type" == "project" ]; then
    gcloud projects get-iam-policy $resource \
      --flatten="bindings[].members" \
      --format="table(bindings.role)" \
      --filter="bindings.role:$role AND bindings.members:$member" 2>/dev/null | grep -q "$role"
  else
    gcloud iam service-accounts get-iam-policy $resource \
      --flatten="bindings[].members" \
      --format="table(bindings.role)" \
      --filter="bindings.role:$role AND bindings.members:$member" 2>/dev/null | grep -q "$role"
  fi
}

# Function to add IAM binding if it doesn't exist
add_iam_binding_if_needed() {
  local member=$1
  local role=$2
  local resource_type=$3
  local resource=$4
  local description=$5
  
  if check_iam_binding "$member" "$role" "$resource_type" "$resource"; then
    echo "✓ IAM binding already exists: $description"
  else
    echo "Adding IAM binding: $description..."
    if [ "$resource_type" == "project" ]; then
      gcloud projects add-iam-policy-binding $resource \
        --member="$member" \
        --role="$role" \
        --condition=None
    else
      gcloud iam service-accounts add-iam-policy-binding $resource \
        --role="$role" \
        --member="$member"
    fi
    echo "✓ IAM binding added: $description"
  fi
}

# Grant IAM roles to the application service account
APP_SA_EMAIL="$APP_SA@$PROJECT_ID.iam.gserviceaccount.com"

add_iam_binding_if_needed \
  "serviceAccount:$APP_SA_EMAIL" \
  "roles/artifactregistry.admin" \
  "project" \
  "$PROJECT_ID" \
  "Artifact Registry Admin for $APP_SA"

add_iam_binding_if_needed \
  "serviceAccount:$APP_SA_EMAIL" \
  "roles/cloudbuild.builds.editor" \
  "project" \
  "$PROJECT_ID" \
  "Cloud Build Editor for $APP_SA"

add_iam_binding_if_needed \
  "serviceAccount:$APP_SA_EMAIL" \
  "roles/run.admin" \
  "project" \
  "$PROJECT_ID" \
  "Cloud Run Admin for $APP_SA"

add_iam_binding_if_needed \
  "serviceAccount:$APP_SA_EMAIL" \
  "roles/storage.admin" \
  "project" \
  "$PROJECT_ID" \
  "Storage Admin for $APP_SA"

# Grant IAM role to the networking service account
NET_SA_EMAIL="$NET_SA@$PROJECT_ID.iam.gserviceaccount.com"

add_iam_binding_if_needed \
  "serviceAccount:$NET_SA_EMAIL" \
  "roles/compute.networkAdmin" \
  "project" \
  "$PROJECT_ID" \
  "Compute Network Admin for $NET_SA"

# Add IAM bindings for workload identity
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
WORKLOAD_MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WORKLOAD_IDENTITY_POOL_NAME/attribute.repository/$GITHUB_OWNER/$GITHUB_REPO"

add_iam_binding_if_needed \
  "$WORKLOAD_MEMBER" \
  "roles/iam.workloadIdentityUser" \
  "service-account" \
  "$NET_SA_EMAIL" \
  "Workload Identity User for $NET_SA"

add_iam_binding_if_needed \
  "$WORKLOAD_MEMBER" \
  "roles/iam.workloadIdentityUser" \
  "service-account" \
  "$APP_SA_EMAIL" \
  "Workload Identity User for $APP_SA"

echo ""
echo "✅ Setup complete! All resources are configured."