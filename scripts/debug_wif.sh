#!/bin/bash

# WIF Debug Script - Comprehensive Diagnostic Tool

set +e  # Don't exit on errors - we want to see everything

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 COMPREHENSIVE WIF DEBUG REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Generated: $(date)"
echo ""

# ==============================================================================
# SECTION 1: ENVIRONMENT VARIABLES
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 SECTION 1: Environment Variables from load_env.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "WIF_PROJECT_ID: ${WIF_PROJECT_ID:-NOT SET}"
echo "PROJECT_PREFIX: ${PROJECT_PREFIX:-NOT SET}"
echo "PROJECT_ENVS: ${PROJECT_ENVS:-NOT SET}"
echo "GH_SA_NAME: ${GH_SA_NAME:-NOT SET}"
echo "RUNTIME_SA_NAME: ${RUNTIME_SA_NAME:-NOT SET}"
echo "GITHUB_ORG_ID: ${GITHUB_ORG_ID:-NOT SET}"
echo "ARTIFACT_LOCATION: ${ARTIFACT_LOCATION:-NOT SET}"
echo "ARTIFACT_REPOSITORY: ${ARTIFACT_REPOSITORY:-NOT SET}"
echo ""

# ==============================================================================
# SECTION 2: PROJECT INFORMATION
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  SECTION 2: GCP Project Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -z "${WIF_PROJECT_ID}" ]; then
  echo "❌ WIF_PROJECT_ID is not set!"
else
  WIF_PROJECT_NUMBER=$(gcloud projects describe "${WIF_PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)
  if [ -z "${WIF_PROJECT_NUMBER}" ]; then
    echo "❌ WIF Project: ${WIF_PROJECT_ID} - NOT FOUND or NO ACCESS"
  else
    echo "✅ WIF Project: ${WIF_PROJECT_ID}"
    echo "   Project Number: ${WIF_PROJECT_NUMBER}"
  fi
fi
echo ""

for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  ENV_PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)
  
  if [ -z "${ENV_PROJECT_NUMBER}" ]; then
    echo "❌ ${ENV} Project: ${PROJECT_ID} - NOT FOUND or NO ACCESS"
  else
    echo "✅ ${ENV} Project: ${PROJECT_ID}"
    echo "   Project Number: ${ENV_PROJECT_NUMBER}"
  fi
done
echo ""

# ==============================================================================
# SECTION 3: WIF POOLS AND PROVIDERS
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 SECTION 3: Workload Identity Federation Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for ENV in $PROJECT_ENVS; do
  POOL_NAME="github-pool-${ENV}"
  PROVIDER_NAME="github-provider-${ENV}"
  
  echo "─────────────────────────────────────────────────────────────────────"
  echo "Environment: ${ENV}"
  echo "─────────────────────────────────────────────────────────────────────"
  
  # Check if pool exists
  POOL_EXISTS=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --format="value(name)" 2>/dev/null)
  
  if [ -z "${POOL_EXISTS}" ]; then
    echo "❌ Pool '${POOL_NAME}' does NOT exist in ${WIF_PROJECT_ID}"
    echo ""
    continue
  else
    echo "✅ Pool '${POOL_NAME}' exists"
  fi
  
  # Check if provider exists and show configuration
  PROVIDER_CONFIG=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="yaml(name,attributeCondition,attributeMapping)" 2>/dev/null)
  
  if [ -z "${PROVIDER_CONFIG}" ]; then
    echo "❌ Provider '${PROVIDER_NAME}' does NOT exist"
    echo ""
    continue
  fi
  
  echo "✅ Provider '${PROVIDER_NAME}' exists"
  echo ""
  echo "Provider Configuration:"
  echo "${PROVIDER_CONFIG}" | sed 's/^/  /'
  echo ""
  
  # Get the full provider resource name
  PROVIDER_RESOURCE=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(name)" 2>/dev/null)
  
  echo "Provider Resource Name (for GitHub secret):"
  echo "  ${PROVIDER_RESOURCE}"
  echo ""
done

# ==============================================================================
# SECTION 4: SERVICE ACCOUNTS AND IAM BINDINGS
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "👤 SECTION 4: Service Accounts and IAM Bindings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  RUNTIME_SA="${RUNTIME_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  
  echo "─────────────────────────────────────────────────────────────────────"
  echo "Environment: ${ENV} (Project: ${PROJECT_ID})"
  echo "─────────────────────────────────────────────────────────────────────"
  
  # Check GitHub Actions SA
  SA_EXISTS=$(gcloud iam service-accounts describe "${GH_SA}" \
    --project="${PROJECT_ID}" \
    --format="value(email)" 2>/dev/null)
  
  if [ -z "${SA_EXISTS}" ]; then
    echo "❌ GitHub Actions SA '${GH_SA}' does NOT exist"
  else
    echo "✅ GitHub Actions SA: ${GH_SA}"
    
    # Get IAM policy
    echo ""
    echo "IAM Policy for GitHub Actions SA:"
    SA_POLICY=$(gcloud iam service-accounts get-iam-policy "${GH_SA}" \
      --project="${PROJECT_ID}" \
      --format="yaml(bindings)" 2>/dev/null)
    
    if [ -z "${SA_POLICY}" ]; then
      echo "  ⚠️  No IAM policy bindings found"
    else
      echo "${SA_POLICY}" | sed 's/^/  /'
      
      # Check if WIF binding exists and which project number it uses
      if echo "${SA_POLICY}" | grep -q "principalSet"; then
        BINDING_PROJECT_NUMBER=$(echo "${SA_POLICY}" | grep -oP 'projects/\K[0-9]+' | head -1)
        echo ""
        echo "WIF Binding Analysis:"
        echo "  Binding references project number: ${BINDING_PROJECT_NUMBER}"
        
        if [ "${BINDING_PROJECT_NUMBER}" = "${WIF_PROJECT_NUMBER}" ]; then
          echo "  ✅ CORRECT - References WIF project number"
        else
          echo "  ❌ WRONG - Should reference WIF project number: ${WIF_PROJECT_NUMBER}"
        fi
      else
        echo ""
        echo "  ❌ No WIF binding (principalSet) found!"
      fi
    fi
  fi
  
  echo ""
  
  # Check Runtime SA
  RUNTIME_EXISTS=$(gcloud iam service-accounts describe "${RUNTIME_SA}" \
    --project="${PROJECT_ID}" \
    --format="value(email)" 2>/dev/null)
  
  if [ -z "${RUNTIME_EXISTS}" ]; then
    echo "❌ Runtime SA '${RUNTIME_SA}' does NOT exist"
  else
    echo "✅ Runtime SA: ${RUNTIME_SA}"
  fi
  
  echo ""
done

# ==============================================================================
# SECTION 5: PROJECT-LEVEL IAM ROLES
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔑 SECTION 5: Project-Level IAM Roles for GitHub Actions SA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  
  echo "─────────────────────────────────────────────────────────────────────"
  echo "Environment: ${ENV}"
  echo "─────────────────────────────────────────────────────────────────────"
  
  PROJECT_ROLES=$(gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${GH_SA}" \
    --format="table[no-heading](bindings.role)" 2>/dev/null)
  
  if [ -z "${PROJECT_ROLES}" ]; then
    echo "⚠️  No project-level roles found for ${GH_SA}"
  else
    echo "Project-level roles for ${GH_SA}:"
    echo "${PROJECT_ROLES}" | sed 's/^/  ✅ /'
  fi
  
  echo ""
  echo "Expected roles:"
  echo "  • roles/run.developer"
  echo "  • roles/artifactregistry.writer"
  echo ""
done

# ==============================================================================
# SECTION 6: GITHUB INFORMATION
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐙 SECTION 6: GitHub Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "From environment variables:"
echo "  GITHUB_ORG_ID: ${GITHUB_ORG_ID:-NOT SET}"
echo ""

# Try to get GitHub user/org info from common patterns
if [ ! -z "${PROJECT_PREFIX}" ]; then
  # Extract potential username/org from project prefix
  echo "Attempting to fetch GitHub user/org information..."
  echo "(This may fail if the project name doesn't match GitHub username)"
  echo ""
  
  # Try common patterns
  for POTENTIAL_NAME in "${PROJECT_PREFIX}" "${PROJECT_PREFIX#nextjs-}" "${PROJECT_PREFIX%-*}"; do
    if [ ! -z "${POTENTIAL_NAME}" ]; then
      echo "Trying: ${POTENTIAL_NAME}"
      
      USER_ID=$(curl -s "https://api.github.com/users/${POTENTIAL_NAME}" 2>/dev/null | grep -o '"id":[0-9]*' | cut -d: -f2)
      if [ ! -z "${USER_ID}" ]; then
        echo "  ✅ Found user: ${POTENTIAL_NAME}"
        echo "     User ID: ${USER_ID}"
        
        if [ "${USER_ID}" = "${GITHUB_ORG_ID}" ]; then
          echo "     ✅ MATCHES configured GITHUB_ORG_ID"
        else
          echo "     ⚠️  DOES NOT MATCH configured GITHUB_ORG_ID (${GITHUB_ORG_ID})"
        fi
        echo ""
      fi
    fi
  done
fi

echo "To manually get your GitHub user/org ID, run:"
echo "  curl -s https://api.github.com/users/YOUR_USERNAME | jq '.id'"
echo "  OR"
echo "  curl -s https://api.github.com/orgs/YOUR_ORG_NAME | jq '.id'"
echo ""

# ==============================================================================
# SECTION 7: EXPECTED GITHUB TOKEN CLAIMS
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 SECTION 7: Expected GitHub OIDC Token Claims"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "For GitHub Actions workflows to authenticate, they must send:"
echo ""
for ENV in $PROJECT_ENVS; do
  case $ENV in
    prod) GITHUB_ENV="production" ;;
    *) GITHUB_ENV="${ENV}" ;;
  esac
  
  echo "Environment: ${ENV}"
  echo "  assertion.repository_owner_id: ${GITHUB_ORG_ID:-<YOUR_ORG_ID>}"
  echo "  assertion.environment: ${GITHUB_ENV}"
  if [ "${ENV}" = "prod" ]; then
    echo "  assertion.ref: refs/heads/main"
  fi
  echo ""
done

echo "Your GitHub workflow MUST include:"
echo ""
echo "  jobs:"
echo "    deploy:"
echo "      environment: dev  # or stage, or production"
echo "      permissions:"
echo "        contents: read"
echo "        id-token: write"
echo ""

# ==============================================================================
# SECTION 8: GITHUB SECRETS NEEDED
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 SECTION 8: Required GitHub Secrets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "For each GitHub environment (Settings → Environments), add these secrets:"
echo ""

for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  POOL_NAME="github-pool-${ENV}"
  PROVIDER_NAME="github-provider-${ENV}"
  
  case $ENV in
    prod) GITHUB_ENV="production" ;;
    *) GITHUB_ENV="${ENV}" ;;
  esac
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "GitHub Environment: ${GITHUB_ENV}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  PROVIDER_RESOURCE=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(name)" 2>/dev/null)
  
  echo ""
  echo "Secret Name: WIF_PROVIDER"
  if [ -z "${PROVIDER_RESOURCE}" ]; then
    echo "Value: ❌ PROVIDER NOT FOUND"
  else
    echo "Value: ${PROVIDER_RESOURCE}"
  fi
  echo ""
  
  echo "Secret Name: SA_EMAIL"
  echo "Value: ${GH_SA}"
  echo ""
done

# ==============================================================================
# SECTION 9: CRITICAL ISSUES SUMMARY
# ==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  SECTION 9: Critical Issues Found"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ISSUES_FOUND=0

# Check if WIF project exists
if [ -z "${WIF_PROJECT_NUMBER}" ]; then
  echo "❌ ISSUE 1: WIF Project '${WIF_PROJECT_ID}' not found or no access"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check if GITHUB_ORG_ID is set
if [ -z "${GITHUB_ORG_ID}" ] || [ "${GITHUB_ORG_ID}" = "NOT SET" ]; then
  echo "❌ ISSUE $((ISSUES_FOUND + 1)): GITHUB_ORG_ID not set in environment variables"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check each environment
for ENV in $PROJECT_ENVS; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  GH_SA="${GH_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  POOL_NAME="github-pool-${ENV}"
  PROVIDER_NAME="github-provider-${ENV}"
  
  # Check if pool exists
  POOL_EXISTS=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --format="value(name)" 2>/dev/null)
  
  if [ -z "${POOL_EXISTS}" ]; then
    echo "❌ ISSUE $((ISSUES_FOUND + 1)): WIF Pool '${POOL_NAME}' does not exist in ${WIF_PROJECT_ID}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  # Check if provider exists
  PROVIDER_EXISTS=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(name)" 2>/dev/null)
  
  if [ -z "${PROVIDER_EXISTS}" ]; then
    echo "❌ ISSUE $((ISSUES_FOUND + 1)): WIF Provider '${PROVIDER_NAME}' does not exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  # Check if SA exists
  SA_EXISTS=$(gcloud iam service-accounts describe "${GH_SA}" \
    --project="${PROJECT_ID}" \
    --format="value(email)" 2>/dev/null)
  
  if [ -z "${SA_EXISTS}" ]; then
    echo "❌ ISSUE $((ISSUES_FOUND + 1)): Service account '${GH_SA}' does not exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  # Check if WIF binding exists
  SA_POLICY=$(gcloud iam service-accounts get-iam-policy "${GH_SA}" \
    --project="${PROJECT_ID}" \
    --format="yaml(bindings)" 2>/dev/null)
  
  if ! echo "${SA_POLICY}" | grep -q "principalSet"; then
    echo "❌ ISSUE $((ISSUES_FOUND + 1)): No WIF binding found for '${GH_SA}'"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  else
    # Check if binding uses correct project number
    BINDING_PROJECT_NUMBER=$(echo "${SA_POLICY}" | grep -oP 'projects/\K[0-9]+' | head -1)
    if [ "${BINDING_PROJECT_NUMBER}" != "${WIF_PROJECT_NUMBER}" ]; then
      echo "❌ ISSUE $((ISSUES_FOUND + 1)): WIF binding for '${GH_SA}' uses wrong project number"
      echo "   Current: ${BINDING_PROJECT_NUMBER}"
      echo "   Expected: ${WIF_PROJECT_NUMBER}"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
  fi
done

if [ $ISSUES_FOUND -eq 0 ]; then
  echo "✅ No critical issues found in configuration!"
else
  echo ""
  echo "Total issues found: ${ISSUES_FOUND}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DEBUG REPORT COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Please share this entire output to help diagnose the issue."
echo ""