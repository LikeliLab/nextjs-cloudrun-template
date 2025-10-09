#!/bin/bash

echo "================================================"
echo "Fixing Workload Identity Federation Binding"
echo "================================================"
echo ""

PROJECT_ID="nextjs-cloudrun-template-dev"
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER="91323983273"

# Set the correct project
gcloud config set project ${PROJECT_ID}

echo "Removing incorrect binding..."
gcloud iam service-accounts remove-iam-policy-binding ${SA_EMAIL} \
  --project ${PROJECT_ID} \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/michaelellis003/michaelellis003/nextjs-cloudrun-template" \
  --quiet

echo "Adding correct binding..."
gcloud iam service-accounts add-iam-policy-binding ${SA_EMAIL} \
  --project ${PROJECT_ID} \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/michaelellis003/nextjs-cloudrun-template" \
  --quiet

echo ""
echo "✅ Workload Identity binding fixed!"
echo ""
echo "Verifying the binding..."
gcloud iam service-accounts get-iam-policy ${SA_EMAIL} --project ${PROJECT_ID}
echo ""
echo "Now try your GitHub Actions deployment again!"