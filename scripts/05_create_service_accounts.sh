#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

# Check if service account exists
service_account_exists() {
  local sa_email=$1
  local project=$2
  gcloud iam service-accounts describe "${sa_email}" \
    --project="${project}" \
    --format="value(email)" 2>/dev/null || echo ""
}

log_created() {
  echo "  ✅ CREATED: $1"
  ((CREATED_COUNT++))
}

log_skipped() {
  echo "  ⏭️  SKIPPED: $1 (already exists)"
}

echo "================================================"
echo "Creating Service Accounts"
echo "================================================"

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  
  echo ""
  echo "Checking service accounts in ${PROJECT_ID}..."
  
  # GitHub Actions service account
  SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
  if [[ -z $(service_account_exists "${SA_EMAIL}" "${PROJECT_ID}") ]]; then
    gcloud iam service-accounts create github-actions \
      --display-name="GitHub Actions Deploy - ${ENV}" \
      --description="Service account for GitHub Actions CI/CD deployments to ${ENV}" \
      --project=${PROJECT_ID} \
      --quiet
    echo "Created github-actions service account in ${PROJECT_ID}"
  else
    echo "github-actions service account in ${PROJECT_ID} already exists"
  fi
  
  # Runtime service account
  RUNTIME_SA_EMAIL="nextjs-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
  if [[ -z $(service_account_exists "${RUNTIME_SA_EMAIL}" "${PROJECT_ID}") ]]; then
    gcloud iam service-accounts create nextjs-runtime \
      --display-name="Cloud Run Runtime - ${ENV}" \
      --description="Service account used by Cloud Run to execute the Next.js application" \
      --project=${PROJECT_ID} \
      --quiet
    echo "Created nextjs-runtime service account in ${PROJECT_ID}"
  else
    echo "nextjs-runtime service account in ${PROJECT_ID} already exists"
  fi
done

echo ""