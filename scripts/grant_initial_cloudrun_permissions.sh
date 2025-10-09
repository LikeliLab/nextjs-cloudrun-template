#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

echo "================================================"
echo "Granting Initial Cloud Run Permissions"
echo "================================================"
echo ""
echo "This grants broader Cloud Run permissions for initial deployment."
echo "After the service exists, you can re-run the main permissions script"
echo "to apply the scoped (more secure) permissions."
echo ""

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
  
  echo "Granting Cloud Run Admin for initial deployment in ${ENV}..."
  
  # Grant Cloud Run Admin (temporary, for initial deployment)
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/run.admin" \
    --quiet
  
  echo "  ✅ Granted Cloud Run Admin for ${SA_EMAIL}"
  echo ""
done

echo "✅ Initial Cloud Run permissions granted for all environments"
echo ""
echo "After your first successful deployment, run this to apply scoped permissions:"
echo "  ./scripts/06_configure_sa_permissions.sh"
echo ""
echo "This will replace the broad admin permissions with scoped service-specific permissions."