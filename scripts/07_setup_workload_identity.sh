#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

# ============================================================================
# Workload Identity Federation for GitHub Actions
# ============================================================================

echo "================================================"
echo "Setting up Workload Identity Federation"
echo "================================================"
echo ""

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
  PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')

  echo "Configuring Workload Identity Federation for ${ENV}..."

  if ! gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
    echo "❌ ERROR: Service account ${SA_EMAIL} does not exist in ${PROJECT_ID}"
    echo "   Create it first with: gcloud iam service-accounts create github-actions --project=${PROJECT_ID}"
    exit 1
  fi

  case ${ENV} in
    prod)
      ATTRIBUTE_CONDITION="assertion.repository == '${GITHUB_OWNER}/${GITHUB_REPO}' && assertion.repository_owner == '${GITHUB_OWNER}' && assertion.ref == 'refs/heads/main'"
      BRANCH_DESC="main branch only"
      ;;
    stage)
      ATTRIBUTE_CONDITION="assertion.repository == '${GITHUB_OWNER}/${GITHUB_REPO}' && assertion.repository_owner == '${GITHUB_OWNER}' && assertion.ref == 'refs/heads/stage'"
      BRANCH_DESC="stage branch only"
      ;;
    dev)
      ATTRIBUTE_CONDITION="assertion.repository == '${GITHUB_OWNER}/${GITHUB_REPO}' && assertion.repository_owner == '${GITHUB_OWNER}' && assertion.ref_type == 'branch' && assertion.ref != 'refs/heads/main' && assertion.ref != 'refs/heads/stage'"
      BRANCH_DESC="any branch except main/stage"
      ;;
  esac
  
  # 1. Create Workload Identity Pool (if it doesn't exist)
  if ! gcloud iam workload-identity-pools describe ${WIF_POOL_ID} \
    --location=global \
    --project=${PROJECT_ID} &>/dev/null; then
    
    gcloud iam workload-identity-pools create ${WIF_POOL_ID} \
      --location=global \
      --project=${PROJECT_ID} \
      --display-name="GitHub Actions Pool" \
      --description="Workload Identity Pool for GitHub Actions" \
      --quiet
    
    echo "  ✅ Created Workload Identity Pool"
  else
    echo "  ⏭️  Workload Identity Pool already exists"
  fi
  
  # 2. Create or Update Workload Identity Provider for GitHub
  if ! gcloud iam workload-identity-pools providers describe ${WIF_PROVIDER_ID} \
    --workload-identity-pool=${WIF_POOL_ID} \
    --location=global \
    --project=${PROJECT_ID} &>/dev/null; then
    
    # Provider doesn't exist - CREATE it
    gcloud iam workload-identity-pools providers create-oidc ${WIF_PROVIDER_ID} \
      --workload-identity-pool=${WIF_POOL_ID} \
      --location=global \
      --project=${PROJECT_ID} \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref,attribute.workflow=assertion.workflow,attribute.job_workflow_ref=assertion.job_workflow_ref" \
      --attribute-condition="${ATTRIBUTE_CONDITION}" \
      --quiet
    
    echo "  ✅ Created GitHub OIDC Provider with branch restriction: ${BRANCH_DESC}"
  else
    # Provider exists - UPDATE it
    gcloud iam workload-identity-pools providers update-oidc ${WIF_PROVIDER_ID} \
      --workload-identity-pool=${WIF_POOL_ID} \
      --location=global \
      --project=${PROJECT_ID} \
      --attribute-condition="${ATTRIBUTE_CONDITION}" \
      --quiet
    
    echo "  🔄 Updated GitHub OIDC Provider with branch restriction: ${BRANCH_DESC}"
  fi
    
  # 3. Grant Service Account Token Creator role to the Workload Identity Pool
  # This allows GitHub Actions to impersonate the service account
  WORKLOAD_IDENTITY_USER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_OWNER}/${GITHUB_REPO}"
  
  echo "  🔍 Expected binding: ${WORKLOAD_IDENTITY_USER}"
    
  # Remove any incorrect bindings first (cleanup)
  echo "  🧹 Cleaning up any incorrect bindings..."
  gcloud iam service-accounts get-iam-policy ${SA_EMAIL} \
    --project=${PROJECT_ID} \
    --format=json 2>/dev/null | \
    jq -r ".bindings[]? | select(.role==\"roles/iam.workloadIdentityUser\") | .members[]? | select(. | contains(\"${WIF_POOL_ID}\"))" 2>/dev/null | \
    while read -r existing_member; do
      if [[ "${existing_member}" != "${WORKLOAD_IDENTITY_USER}" ]]; then
        echo "  🗑️  Removing incorrect binding: ${existing_member}"
        gcloud iam service-accounts remove-iam-policy-binding ${SA_EMAIL} \
          --project=${PROJECT_ID} \
          --role="roles/iam.workloadIdentityUser" \
          --member="${existing_member}" \
          --quiet 2>/dev/null || true
      fi
    done
  
  # Check if correct binding exists
  EXISTING_BINDING=$(gcloud iam service-accounts get-iam-policy ${SA_EMAIL} \
    --project=${PROJECT_ID} \
    --format=json 2>/dev/null | jq -r ".bindings[] | select(.role==\"roles/iam.workloadIdentityUser\") | .members[] | select(. == \"${WORKLOAD_IDENTITY_USER}\")" 2>/dev/null || echo "")
  
  if [[ -z "${EXISTING_BINDING}" ]]; then
    echo "  ➕ Adding correct binding..."
    gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
      --project=${PROJECT_ID} \
      --role="roles/iam.workloadIdentityUser" \
      --member="${WORKLOAD_IDENTITY_USER}" \
      --quiet
    
    echo "  ✅ Granted Workload Identity User role"
  else
    echo "  ⏭️  Correct Workload Identity User role already exists"
  fi
  
  # 4. Output the provider resource name for GitHub Actions
  PROVIDER_RESOURCE_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
  
  echo ""
  echo "  📋 GitHub Actions configuration for ${ENV}:"
  echo "  ----------------------------------------"
  echo "  workload_identity_provider: '${PROVIDER_RESOURCE_NAME}'"
  echo "  service_account: '${SA_EMAIL}'"
  echo "  Allowed from: ${GITHUB_OWNER}/${GITHUB_REPO}"
done

echo "================================================"
echo "✅ Workload Identity Federation Setup Complete"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Copy the configuration values above to your GitHub Actions secrets"
echo "2. Update your workflow files to use WIF authentication"
echo "3. Delete any existing service account keys"
echo ""
