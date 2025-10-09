# GitHub Actions Workflows

This directory contains the CI/CD workflows for deploying the Next.js application to Google Cloud Run across three environments.

## Workflows

### 1. CI (`ci.yml`)
- **Triggers**: Pull requests and pushes to `main` and `stage` branches
- **Purpose**: Runs linting, type checking, building, and security scanning
- **Jobs**:
  - `lint-and-test`: ESLint, TypeScript check, and build verification
  - `security-scan`: npm audit and Trivy vulnerability scanning

### 2. Dev Deployment (`deploy-dev.yml`)
- **Triggers**: Pushes to any branch except `main` and `stage`
- **Purpose**: Deploys to development environment for feature branch testing
- **Environment**: Lightweight configuration with auto-scaling to zero

### 3. Stage Deployment (`deploy-stage.yml`)
- **Triggers**: Pushes to `stage` branch
- **Purpose**: Deploys to staging environment for pre-production testing
- **Features**: Includes smoke tests and maintains minimum 1 instance

### 4. Production Deployment (`deploy-prod.yml`)
- **Triggers**: Pushes to `main` branch
- **Purpose**: Deploys to production with blue-green deployment strategy
- **Features**: 
  - Gradual traffic shifting (10% → 50% → 100%)
  - Production health checks
  - High-availability configuration with minimum 2 instances

## Required Secrets

Add these secrets to your GitHub repository:

```
WIF_PROVIDER_DEV=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
WIF_PROVIDER_STAGE=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github  
WIF_PROVIDER_PROD=projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
SA_EMAIL_DEV=github-actions@PROJECT_PREFIX-dev.iam.gserviceaccount.com
SA_EMAIL_STAGE=github-actions@PROJECT_PREFIX-stage.iam.gserviceaccount.com
SA_EMAIL_PROD=github-actions@PROJECT_PREFIX-prod.iam.gserviceaccount.com
PROJECT_ID_DEV=PROJECT_PREFIX-dev
PROJECT_ID_STAGE=PROJECT_PREFIX-stage
PROJECT_ID_PROD=PROJECT_PREFIX-prod
ARTIFACT_REGISTRY_REPO=docker-repo
```

## Setup Steps

1. Run your infrastructure setup scripts:
   ```bash
   ./scripts/01_create_projects.sh
   ./scripts/02_grant_initial_permissions.sh
   ./scripts/03_enable_required_apis.sh
   ./scripts/04_create_artifact_registry.sh
   ./scripts/05_create_service_accounts.sh
   ./scripts/06_configure_sa_permissions.sh
   ./scripts/07_setup_workload_identity.sh
   ```

2. Copy the workload identity provider and service account values from the script output

3. Add the values as GitHub repository secrets

4. Create a production environment in GitHub:
   - Go to Settings → Environments
   - Create "production" environment
   - Add protection rules if desired

## Branch Strategy

- **Feature branches**: Deploy to dev environment
- **`stage` branch**: Deploy to staging environment  
- **`main` branch**: Deploy to production environment

## Security Features

- Workload Identity Federation (no service account keys)
- Branch-based environment restrictions
- Vulnerability scanning with Trivy
- npm audit for dependency vulnerabilities
- SARIF upload to GitHub Security tab