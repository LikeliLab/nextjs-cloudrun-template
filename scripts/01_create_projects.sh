# This script is part of a Next.js Cloud Run template project.
# It is intended to create and set up necessary projects or resources
# for deploying a Next.js application to Google Cloud Run.
# Ensure you have the required permissions and tools (e.g., gcloud CLI) 
# installed before running this script.

#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in dev stage prod; do
    PROJECT_ID="${PROJECT_PREFIX}-$ENV"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo "Project $PROJECT_ID already exists, skipping creation"
    else
        echo "Creating project $PROJECT_ID..."
        if gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID"; then
            echo "Project $PROJECT_ID created successfully"
        else
            echo "Failed to create project $PROJECT_ID" >&2
            continue
        fi
    fi
    
    # Check if billing account is already linked
    CURRENT_BILLING=$(gcloud billing projects describe "$PROJECT_ID" \
        --format="value(billingAccountName)" 2>/dev/null)
    
    if [ -n "$CURRENT_BILLING" ]; then
        if [[ "$CURRENT_BILLING" == *"$BILLING_ACCOUNT"* ]]; then
            echo "Billing account already linked to $PROJECT_ID"
        else
            echo "Different billing account linked to $PROJECT_ID: $CURRENT_BILLING"
            echo "Updating to $BILLING_ACCOUNT..."
            gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
        fi
    else
        echo "Linking billing account to $PROJECT_ID..."
        if gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"; then
            echo "Billing account linked successfully"
        else
            echo "Failed to link billing account to $PROJECT_ID" >&2
        fi
    fi
    
    echo "---"
done

echo "Setup complete!"