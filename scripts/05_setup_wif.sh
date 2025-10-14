#!/bin/bash
set -e # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

# ============================================================================
# VALIDATION: Check that GITHUB_ORG_ID is numeric
# ============================================================================
echo "Validating configuration..."

if ! [[ "$GITHUB_ORG_ID" =~ ^[0-9]+$ ]]; then
  echo ""
  echo "❌ ERROR: GITHUB_ORG_ID must be a numeric user ID, not a username!"
  echo ""
  echo "Current value: ${GITHUB_ORG_ID}"
  echo ""
  echo "To get your numeric GitHub user ID, run:"
  echo "  curl -s https://api.github.com/users/YOUR_USERNAME | grep '\"id\":' | head -1 | grep -o '[0-9]*'"
  echo ""
  echo "Then update scripts/.env with the numeric value."
  echo ""
  exit 1
fi

echo "✅ GITHUB_ORG_ID is numeric: ${GITHUB_ORG_ID}"
echo ""

# Get WIF project number ONCE at the beginning
WIF_PROJECT_NUMBER=$(gcloud projects describe "${WIF_PROJECT_ID}" --format="value(projectNumber)")

echo "========================================="
echo "WIF Management Project: ${WIF_PROJECT_ID}"
echo "WIF Project Number: ${WIF_PROJECT_NUMBER}"
echo "GitHub User ID: ${GITHUB_ORG_ID}"
echo "========================================="
echo ""

# Function to check if WIF pool exists
pool_exists() {
  local pool_name=$1
  gcloud iam workload-identity-pools describe "${pool_name}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --format="value(name)" &>/dev/null
  return $?
}

# Function to check if WIF provider exists
provider_exists() {
  local provider_name=$1
  local pool_name=$2
  gcloud iam workload-identity-pools providers describe "${provider_name}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${pool_name}" \
    --format="value(name)" &>/dev/null
  return $?
}

# Function to check if service account has WIF binding
sa_has_wif_binding() {
  local sa_email=$1
  local project_id=$2
  gcloud iam service-accounts get-iam-policy "${sa_email}" \
    --project="${project_id}" \
    --format="value(bindings.members)" 2>/dev/null | grep -q "principalSet"
  return $?
}

for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  POOL_NAME="github-pool-${ENV}"
  PROVIDER_NAME="github-provider-${ENV}"
  
  echo "========================================="
  echo "Setting up WIF for: ${PROJECT_ID} (${ENV})"
  echo "========================================="
  
  # 1. Create Workload Identity Pool
  echo -n "Workload Identity Pool (${POOL_NAME})... "
  if pool_exists "${POOL_NAME}"; then
    echo "✓ Already exists"
  else
    if gcloud iam workload-identity-pools create "${POOL_NAME}" \
      --project="${WIF_PROJECT_ID}" \
      --location="global" \
      --display-name="GitHub Actions ${ENV} Pool" 2>/dev/null; then
      echo "✓ Created"
    else
      echo "⚠ Failed to create (may have been created concurrently)"
    fi
  fi
  
  # 2. Create OIDC provider with security-hardened attribute mappings
  echo -n "OIDC Provider (${PROVIDER_NAME})... "
  
  ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id,attribute.environment=assertion.environment,attribute.ref=assertion.ref"
if [ "${ENV}" == "prod" ]; then
    CONDITION="assertion.repository_owner_id == '${GITHUB_ORG_ID}' && assertion.environment == '${ENV}' && assertion.ref == 'refs/heads/main'"
else
    CONDITION="assertion.repository_owner_id == '${GITHUB_ORG_ID}' && assertion.environment == '${ENV}' && assertion.ref == 'refs/heads/${ENV}'"
fi
  
  if provider_exists "${PROVIDER_NAME}" "${POOL_NAME}"; then
    echo "✓ Already exists"
    if gcloud iam workload-identity-pools providers update-oidc "${PROVIDER_NAME}" \
      --project="${WIF_PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${POOL_NAME}" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${CONDITION}" 2>/dev/null; then
      echo "✓ Updated condition"
     else
      echo "⚠ Failed to update (may have been created concurrently)"
    fi
  else
    if gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
      --project="${WIF_PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${POOL_NAME}" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${CONDITION}" 2>/dev/null; then
      echo "✓ Created"
    else
      echo "⚠ Failed to create (may have been created concurrently)"
    fi
  fi
  
  # 3. Bind service account to WIF pool
  GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  
  echo -n "Service Account WIF Binding (${GH_SA})... "
  
  if sa_has_wif_binding "${GH_SA}" "${PROJECT_ID}"; then
    echo "✓ Already bound"
  else
    if gcloud iam service-accounts add-iam-policy-binding "${GH_SA}" \
      --project="${PROJECT_ID}" \
      --role="roles/iam.workloadIdentityUser" \
      --member="principalSet://iam.googleapis.com/projects/${WIF_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.environment/${GITHUB_ENV}" 2>/dev/null; then
      echo "✓ Bound"
    else
      echo "⚠ Failed to bind (may already be bound)"
    fi
  fi
  
  # 4. Get WIF provider resource name
  echo -n "Retrieving WIF provider resource name... "
  PROVIDER_RESOURCE=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(name)" 2>/dev/null)
  
  if [ -n "${PROVIDER_RESOURCE}" ]; then
    echo "✓ Retrieved"
  else
    echo "✗ Failed to retrieve"
    continue
  fi
  
  # 5. Output GitHub secrets
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ Setup Complete for ${PROJECT_ID}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "🔐 GitHub Secrets for '${GITHUB_ENV}' environment:"
  echo ""
  echo "  Name:  WIF_PROVIDER"
  echo "  Value: ${PROVIDER_RESOURCE}"
  echo ""
  echo "  Name:  SA_EMAIL"
  echo "  Value: ${GH_SA}"
  echo ""
  
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 All environments configured successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"