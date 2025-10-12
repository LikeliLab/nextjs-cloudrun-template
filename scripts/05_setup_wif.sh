#!/bin/bash
set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"
    PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    
    echo "========================================="
    echo "Setting up WIF for project: $PROJECT_ID"
    echo "Project Number: $PROJECT_NUMBER"
    echo "========================================="
    
    # 1. Create service account if it doesn't exist
    echo "Checking GitHub Actions service account..."
    if gcloud iam service-accounts describe "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" &>/dev/null; then
        echo "✓ Service account already exists"
    else
        echo "Creating service account..."
        gcloud iam service-accounts create github-actions \
            --project="${PROJECT_ID}" \
            --display-name="GitHub Actions Service Account" \
            --description="Service account for GitHub Actions deployments"
        echo "✓ Service account created"
    fi
    
    # 2. Grant necessary roles
    echo "Granting IAM roles..."
    for role in "roles/run.admin" "roles/storage.admin" "roles/artifactregistry.admin" "roles/clouddeploy.admin"; do
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" \
            --condition=None \
            --quiet 2>/dev/null || echo "✓ Role ${role} already exists"
    done
    echo "✓ IAM roles configured"
    
    # 3. Create workload identity pool if it doesn't exist
    echo "Checking workload identity pool..."
    if gcloud iam workload-identity-pools describe "nextjs-app-dev" \
        --project="${PROJECT_ID}" \
        --location="global" &>/dev/null; then
        echo "✓ Workload identity pool already exists"
    else
        echo "Creating workload identity pool..."
        gcloud iam workload-identity-pools create "nextjs-app-dev" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --display-name="Nextjs app pool"
        echo "✓ Workload identity pool created"
    fi
    
    # 4. Handle OIDC provider (check for DELETED state)
    echo "Checking OIDC provider..."
    PROVIDER_STATE=$(gcloud iam workload-identity-pools providers describe "github-oidc" \
        --project="${PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="nextjs-app-dev" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROVIDER_STATE" = "DELETED" ]; then
        echo "⚠ Provider is in DELETED state. Undeleting..."
        gcloud iam workload-identity-pools providers undelete "github-oidc" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool="nextjs-app-dev"
        echo "✓ Provider undeleted"
        
        # Check if attribute mapping is correct
        CURRENT_MAPPING=$(gcloud iam workload-identity-pools providers describe "github-oidc" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool="nextjs-app-dev" \
            --format="value(attributeMapping)" 2>/dev/null)
        
        if [[ ! "$CURRENT_MAPPING" == *"attribute.repository"* ]]; then
            echo "⚠ Provider has incorrect attribute mapping. Deleting and recreating..."
            gcloud iam workload-identity-pools providers delete "github-oidc" \
                --project="${PROJECT_ID}" \
                --location="global" \
                --workload-identity-pool="nextjs-app-dev" \
                --quiet
            PROVIDER_STATE="NOT_FOUND"
        fi
    fi
    
    if [ "$PROVIDER_STATE" = "NOT_FOUND" ]; then
        echo "Creating OIDC provider with correct attribute mapping..."
        gcloud iam workload-identity-pools providers create-oidc "github-oidc" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool="nextjs-app-dev" \
            --display-name="GitHub OIDC Provider" \
            --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
            --attribute-condition="assertion.repository_owner=='${GITHUB_OWNER}'" \
            --issuer-uri="https://token.actions.githubusercontent.com"
        echo "✓ OIDC provider created"
    elif [ "$PROVIDER_STATE" = "ACTIVE" ]; then
        # Verify attribute mapping
        CURRENT_MAPPING=$(gcloud iam workload-identity-pools providers describe "github-oidc" \
            --project="${PROJECT_ID}" \
            --location="global" \
            --workload-identity-pool="nextjs-app-dev" \
            --format="value(attributeMapping)" 2>/dev/null)
        
        if [[ ! "$CURRENT_MAPPING" == *"attribute.repository"* ]]; then
            echo "⚠ Provider exists but has incorrect attribute mapping. Recreating..."
            gcloud iam workload-identity-pools providers delete "github-oidc" \
                --project="${PROJECT_ID}" \
                --location="global" \
                --workload-identity-pool="nextjs-app-dev" \
                --quiet
            
            gcloud iam workload-identity-pools providers create-oidc "github-oidc" \
                --project="${PROJECT_ID}" \
                --location="global" \
                --workload-identity-pool="nextjs-app-dev" \
                --display-name="GitHub OIDC Provider" \
                --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
                --attribute-condition="assertion.repository_owner=='${GITHUB_OWNER}'" \
                --issuer-uri="https://token.actions.githubusercontent.com"
            echo "✓ OIDC provider recreated with correct mapping"
        else
            echo "✓ OIDC provider already exists with correct configuration"
        fi
    fi
    
    # 5. Bind service account to workload identity pool
    echo "Configuring workload identity binding..."
    gcloud iam service-accounts add-iam-policy-binding "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/nextjs-app-dev/attribute.repository/${GITHUB_OWNER}/${GITHUB_REPO}" \
        --condition=None \
        --quiet 2>/dev/null || echo "✓ Workload identity binding already exists"
    
    echo "✓ Workload identity binding configured"
    
    # 6. Output GitHub secrets
    echo ""
    echo "==========================================="
    echo "✅ Setup Complete for ${PROJECT_ID}"
    echo "==========================================="
    echo ""
    echo "Add these secrets to your GitHub repository:"
    echo "(Settings → Secrets and variables → Actions)"
    echo ""
    echo "Secret Name: WIF_PROVIDER"
    echo "Value: projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/nextjs-app-dev/providers/github-oidc"
    echo ""
    echo "Secret Name: WIF_SERVICE_ACCOUNT"
    echo "Value: github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "==========================================="
    echo ""
done

echo "🎉 All environments configured successfully!"