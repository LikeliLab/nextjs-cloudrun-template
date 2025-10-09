#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
# Track what was created vs skipped
CREATED_COUNT=0
SKIPPED_COUNT=0
UPDATED_COUNT=0

log_created() {
  echo "  ✅ CREATED: $1"
  ((CREATED_COUNT++))
}

log_skipped() {
  echo "  ⏭️  SKIPPED: $1 (already exists)"
  ((SKIPPED_COUNT++))
}

log_updated() {
  echo "  🔄 UPDATED: $1"
  ((UPDATED_COUNT++))
}

custom_role_exists() {
  local role_name=$1
  local project=$2
  gcloud iam roles describe "${role_name}" \
    --project="${project}" \
    --format="value(name)" 2>/dev/null || echo ""
}

# Check if a project-level IAM binding exists
iam_binding_exists() {
  local project=$1
  local member=$2
  local role=$3
  local condition_title=${4:-""}
  
  if [[ -n "${condition_title}" ]]; then
    # Check for binding with specific condition
    gcloud projects get-iam-policy "${project}" \
      --flatten="bindings[].members" \
      --filter="bindings.role:${role} AND bindings.members:${member} AND bindings.condition.title:${condition_title}" \
      --format="value(bindings.role)" 2>/dev/null | grep -q "${role}"
  else
    # Check for unconditional binding
    gcloud projects get-iam-policy "${project}" \
      --flatten="bindings[].members" \
      --filter="bindings.role:${role} AND bindings.members:${member} AND NOT bindings.condition.title:*" \
      --format="value(bindings.role)" 2>/dev/null | grep -q "${role}"
  fi
}

# Check if an Artifact Registry repository IAM binding exists
repo_iam_binding_exists() {
  local repo_name=$1
  local location=$2
  local member=$3
  local role=$4
  local project=$5
  
  gcloud artifacts repositories get-iam-policy "${repo_name}" \
    --location="${location}" \
    --project="${project}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:${role} AND bindings.members:${member}" \
    --format="value(bindings.role)" 2>/dev/null | grep -q "${role}"
}

# Check if a service account IAM binding exists
sa_iam_binding_exists() {
  local sa_email=$1
  local member=$2
  local role=$3
  local project=$4
  
  gcloud iam service-accounts get-iam-policy "${sa_email}" \
    --project="${project}" \
    --flatten="bindings[].members" \
    --filter="bindings.role:${role} AND bindings.members:${member}" \
    --format="value(bindings.role)" 2>/dev/null | grep -q "${role}"
}

# Create custom Artifact Registry Pusher role (no delete permissions)
create_artifact_registry_pusher_role() {
  local PROJECT_ID=$1
  local ROLE_NAME="ArtifactRegistryPusher"
  
  if [[ -z $(custom_role_exists "${ROLE_NAME}" "${PROJECT_ID}") ]]; then
    gcloud iam roles create ${ROLE_NAME} \
      --project=${PROJECT_ID} \
      --title="Artifact Registry Pusher (No Delete)" \
      --description="Upload and manage container images without deletion permissions" \
      --permissions=artifactregistry.dockerimages.get,artifactregistry.dockerimages.list,artifactregistry.files.get,artifactregistry.files.list,artifactregistry.files.upload,artifactregistry.packages.get,artifactregistry.packages.list,artifactregistry.repositories.downloadArtifacts,artifactregistry.repositories.get,artifactregistry.repositories.list,artifactregistry.repositories.uploadArtifacts,artifactregistry.tags.create,artifactregistry.tags.get,artifactregistry.tags.list,artifactregistry.tags.update,artifactregistry.versions.get,artifactregistry.versions.list \
      --stage=GA \
      --quiet
    log_created "Custom ArtifactRegistryPusher role"
  else
    gcloud iam roles update ${ROLE_NAME} \
      --project=${PROJECT_ID} \
      --permissions=artifactregistry.dockerimages.get,artifactregistry.dockerimages.list,artifactregistry.dockerimages.update,artifactregistry.files.get,artifactregistry.files.list,artifactregistry.files.upload,artifactregistry.packages.get,artifactregistry.packages.list,artifactregistry.packages.update,artifactregistry.repositories.downloadArtifacts,artifactregistry.repositories.get,artifactregistry.repositories.list,artifactregistry.repositories.uploadArtifacts,artifactregistry.tags.create,artifactregistry.tags.get,artifactregistry.tags.list,artifactregistry.tags.update,artifactregistry.versions.get,artifactregistry.versions.list \
      --quiet 2>/dev/null || true
    log_updated "Custom ArtifactRegistryPusher role"
  fi
}

# ============================================================================
# PHASE 1: Configure Runtime Service Account Permissions
# ============================================================================

echo "================================================"
echo "PHASE 1: Configuring Runtime Service Accounts"
echo "================================================"
echo ""
echo "Runtime SAs need operational permissions for logging, tracing, and monitoring"
echo ""

for ENV in dev stage prod; do
  PROJECT_ID="${PROJECT_PREFIX}-${ENV}"
  RUNTIME_SA_EMAIL="${CLOUD_RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  
  echo "Configuring runtime SA for ${ENV}..."

  if ! gcloud iam service-accounts describe ${RUNTIME_SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
    echo "❌ ERROR: Runtime service account ${RUNTIME_SA_EMAIL} does not exist in ${PROJECT_ID}"
    echo "   Create it first with: gcloud iam service-accounts create ${CLOUD_RUN_SA_NAME} --project=${PROJECT_ID}"
    exit 1
  fi
  
  # Cloud Logging Writer
  if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${RUNTIME_SA_EMAIL}" "roles/logging.logWriter"; then
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
      --role="roles/logging.logWriter" \
      --condition=None \
      --quiet
    log_created "Cloud Logging Writer for runtime SA in ${ENV}"
  else
    log_skipped "Cloud Logging Writer for runtime SA in ${ENV}"
  fi
  
  # Cloud Trace Writer (for APM/distributed tracing)
  if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${RUNTIME_SA_EMAIL}" "roles/cloudtrace.agent"; then
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
      --role="roles/cloudtrace.agent" \
      --condition=None \
      --quiet
    log_created "Cloud Trace Agent for runtime SA in ${ENV}"
  else
    log_skipped "Cloud Trace Agent for runtime SA in ${ENV}"
  fi
  
  # Error Reporting Writer (for automatic error tracking)
  if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${RUNTIME_SA_EMAIL}" "roles/errorreporting.writer"; then
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
      --role="roles/errorreporting.writer" \
      --condition=None \
      --quiet
    log_created "Error Reporting Writer for runtime SA in ${ENV}"
  else
    log_skipped "Error Reporting Writer for runtime SA in ${ENV}"
  fi
  
  # Cloud Monitoring Metric Writer (for custom metrics)
  if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${RUNTIME_SA_EMAIL}" "roles/monitoring.metricWriter"; then
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
      --role="roles/monitoring.metricWriter" \
      --condition=None \
      --quiet
    log_created "Monitoring Metric Writer for runtime SA in ${ENV}"
  else
    log_skipped "Monitoring Metric Writer for runtime SA in ${ENV}"
  fi
  
  # Secret Manager accessor (scoped to app-specific secrets)
  if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${RUNTIME_SA_EMAIL}" "roles/secretmanager.secretAccessor" "AppSecretsOnly"; then
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
      --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
      --role="roles/secretmanager.secretAccessor" \
      --condition="expression=resource.name.extract('secrets/{secret}').startsWith('${SECRET_PREFIX}-'),title=AppSecretsOnly" \
      --quiet
    log_created "Secret Manager accessor (scoped to ${SECRET_PREFIX}-*) for runtime SA in ${ENV}"
  else
    log_skipped "Secret Manager accessor for runtime SA in ${ENV}"
  fi
  
  echo ""
done

echo "✅ Runtime service account configuration complete"
echo ""

# ============================================================================
# PHASE 2: Configure PRODUCTION Permissions (Least Privilege)
# ============================================================================

echo "================================================"
echo "PHASE 2: Configuring PRODUCTION (Least Privilege)"
echo "================================================"

PROJECT_ID="${PROJECT_PREFIX}-prod"
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA_EMAIL="${CLOUD_RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "Configuring production deployment permissions..."

if ! gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: GitHub Actions service account ${SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create github-actions --project=${PROJECT_ID}"
  exit 1
fi

if ! gcloud iam service-accounts describe ${RUNTIME_SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: Runtime service account ${RUNTIME_SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create ${CLOUD_RUN_SA_NAME} --project=${PROJECT_ID}"
  exit 1
fi

# 1. Cloud Run Developer (scoped to region for initial deployment)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/run.developer" "RegionScopedCloudRun"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/run.developer" \
    --condition='expression=resource.name.startsWith("projects/'${PROJECT_ID}'/locations/'${CLOUD_RUN_REGION}'/services/"),title=RegionScopedCloudRun,description=Deploy to '${CLOUD_RUN_REGION}' region only' \
    --quiet
  log_created "Cloud Run Developer (scoped to ${CLOUD_RUN_REGION} region) for ${SA_EMAIL}"
else
  log_skipped "Cloud Run Developer for ${SA_EMAIL}"
fi

# 2. Artifact Registry Reader (project-level, needed for Docker authentication)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/artifactregistry.reader"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.reader" \
    --condition=None \
    --quiet
  log_created "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
fi

# 3. Create and apply custom Artifact Registry Pusher role (NO DELETE)
create_artifact_registry_pusher_role "${PROJECT_ID}"

if ! gcloud iam roles describe ArtifactRegistryPusher --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: Failed to create/update custom role"
  exit 1
fi

if ! repo_iam_binding_exists "${ARTIFACT_REGISTRY_NAME}" "${ARTIFACT_REGISTRY_LOCATION}" "serviceAccount:${SA_EMAIL}" "projects/${PROJECT_ID}/roles/ArtifactRegistryPusher" "${PROJECT_ID}"; then
  gcloud artifacts repositories add-iam-policy-binding ${ARTIFACT_REGISTRY_NAME} \
    --location=${ARTIFACT_REGISTRY_LOCATION} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="projects/${PROJECT_ID}/roles/ArtifactRegistryPusher" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Artifact Registry Pusher role (no delete) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Pusher role for ${SA_EMAIL}"
fi

# 4. Service Account User (SCOPED to runtime SA only)
if ! sa_iam_binding_exists "${RUNTIME_SA_EMAIL}" "serviceAccount:${SA_EMAIL}" "roles/iam.serviceAccountUser" "${PROJECT_ID}"; then
  gcloud iam service-accounts add-iam-policy-binding ${RUNTIME_SA_EMAIL} \
    --role="roles/iam.serviceAccountUser" \
    --member="serviceAccount:${SA_EMAIL}" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Service Account User role (scoped to runtime SA)"
else
  log_skipped "Service Account User role (scoped to runtime SA)"
fi

echo ""
echo "✅ Production configuration complete"

# ============================================================================
# PHASE 3: Configure STAGE Permissions (Moderate)
# ============================================================================

echo ""
echo "================================================"
echo "PHASE 3: Configuring STAGE (Moderate Permissions)"
echo "================================================"

PROJECT_ID="${PROJECT_PREFIX}-stage"
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA_EMAIL="${CLOUD_RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "Configuring stage deployment permissions..."

if ! gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: GitHub Actions service account ${SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create github-actions --project=${PROJECT_ID}"
  exit 1
fi

if ! gcloud iam service-accounts describe ${RUNTIME_SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: Runtime service account ${RUNTIME_SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create ${CLOUD_RUN_SA_NAME} --project=${PROJECT_ID}"
  exit 1
fi

# 1. Cloud Run Developer (scoped to specific service)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/run.developer" "AppServiceAccess"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/run.developer" \
    --condition='expression=resource.name.startsWith("projects/'${PROJECT_ID}'/locations/'${CLOUD_RUN_REGION}'/services/'${APP_NAME}'"),title=AppServiceAccess,description=Deploy '${APP_NAME}' service and its revisions' \
    --quiet
  log_created "Cloud Run Developer (scoped to ${APP_NAME} service) for ${SA_EMAIL}"
else
  log_skipped "Cloud Run Developer for ${SA_EMAIL}"
fi

# 2. Artifact Registry Reader (project-level, needed for Docker authentication)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/artifactregistry.reader"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.reader" \
    --condition=None \
    --quiet
  log_created "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
fi

# 3. Create and apply custom Artifact Registry Pusher role (NO DELETE)
create_artifact_registry_pusher_role "${PROJECT_ID}"

if ! gcloud iam roles describe ArtifactRegistryPusher --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: Failed to create/update custom role"
  exit 1
fi

if ! repo_iam_binding_exists "${ARTIFACT_REGISTRY_NAME}" "${ARTIFACT_REGISTRY_LOCATION}" "serviceAccount:${SA_EMAIL}" "projects/${PROJECT_ID}/roles/ArtifactRegistryPusher" "${PROJECT_ID}"; then
  gcloud artifacts repositories add-iam-policy-binding ${ARTIFACT_REGISTRY_NAME} \
    --location=${ARTIFACT_REGISTRY_LOCATION} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="projects/${PROJECT_ID}/roles/ArtifactRegistryPusher" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Artifact Registry Pusher role (no delete) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Pusher role for ${SA_EMAIL}"
fi

# 4. Service Account User (scoped to runtime SA)
if ! sa_iam_binding_exists "${RUNTIME_SA_EMAIL}" "serviceAccount:${SA_EMAIL}" "roles/iam.serviceAccountUser" "${PROJECT_ID}"; then
  gcloud iam service-accounts add-iam-policy-binding ${RUNTIME_SA_EMAIL} \
    --role="roles/iam.serviceAccountUser" \
    --member="serviceAccount:${SA_EMAIL}" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Service Account User role (scoped to runtime SA)"
else
  log_skipped "Service Account User role (scoped to runtime SA)"
fi

echo ""
echo "✅ Stage configuration complete"

# ============================================================================
# PHASE 4: Configure DEVELOPMENT Permissions (Permissive)
# ============================================================================

echo ""
echo "================================================"
echo "PHASE 4: Configuring DEVELOPMENT (Permissive)"
echo "================================================"

PROJECT_ID="${PROJECT_PREFIX}-dev"
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA_EMAIL="${CLOUD_RUN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "Configuring dev deployment permissions..."

if ! gcloud iam service-accounts describe ${SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: GitHub Actions service account ${SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create github-actions --project=${PROJECT_ID}"
  exit 1
fi

if ! gcloud iam service-accounts describe ${RUNTIME_SA_EMAIL} --project=${PROJECT_ID} &>/dev/null; then
  echo "❌ ERROR: Runtime service account ${RUNTIME_SA_EMAIL} does not exist in ${PROJECT_ID}"
  echo "   Create it first with: gcloud iam service-accounts create ${CLOUD_RUN_SA_NAME} --project=${PROJECT_ID}"
  exit 1
fi

# 1. Cloud Run Developer (region-scoped for dev, allows service creation)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/run.developer" "RegionScopedCloudRun"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/run.developer" \
    --condition='expression=resource.name.startsWith("projects/'${PROJECT_ID}'/locations/'${CLOUD_RUN_REGION}'/services/"),title=RegionScopedCloudRun,description=Deploy to '${CLOUD_RUN_REGION}' region only' \
    --quiet
  log_created "Cloud Run Developer (scoped to ${CLOUD_RUN_REGION} region) for ${SA_EMAIL}"
else
  log_skipped "Cloud Run Developer for ${SA_EMAIL}"
fi

# 2. Artifact Registry Reader (project-level, needed for Docker authentication)
if ! iam_binding_exists "${PROJECT_ID}" "serviceAccount:${SA_EMAIL}" "roles/artifactregistry.reader"; then
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.reader" \
    --condition=None \
    --quiet
  log_created "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Reader (project-level) for ${SA_EMAIL}"
fi

# 3. Artifact Registry Writer (FULL access in dev - including delete)
if ! repo_iam_binding_exists "${ARTIFACT_REGISTRY_NAME}" "${ARTIFACT_REGISTRY_LOCATION}" "serviceAccount:${SA_EMAIL}" "roles/artifactregistry.writer" "${PROJECT_ID}"; then
  gcloud artifacts repositories add-iam-policy-binding ${ARTIFACT_REGISTRY_NAME} \
    --location=${ARTIFACT_REGISTRY_LOCATION} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.writer" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Artifact Registry Writer role (full access) for ${SA_EMAIL}"
else
  log_skipped "Artifact Registry Writer role for ${SA_EMAIL}"
fi

# 4. Service Account User (scoped to runtime SA)
if ! sa_iam_binding_exists "${RUNTIME_SA_EMAIL}" "serviceAccount:${SA_EMAIL}" "roles/iam.serviceAccountUser" "${PROJECT_ID}"; then
  gcloud iam service-accounts add-iam-policy-binding ${RUNTIME_SA_EMAIL} \
    --role="roles/iam.serviceAccountUser" \
    --member="serviceAccount:${SA_EMAIL}" \
    --project=${PROJECT_ID} \
    --quiet
  log_created "Service Account User role (scoped to runtime SA)"
else
  log_skipped "Service Account User role (scoped to runtime SA)"
fi

echo ""
echo "✅ Dev configuration complete"
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "================================================"
echo "CONFIGURATION SUMMARY"
echo "================================================"
echo ""
echo "Created: ${CREATED_COUNT}"
echo "Updated: ${UPDATED_COUNT}"
echo "Skipped: ${SKIPPED_COUNT}"
echo ""
echo "✅ All environments configured for GitHub Actions deployment"
echo ""
echo "Runtime SAs have:"
echo "  - Cloud Logging (for console.log)"
echo "  - Cloud Trace (for performance monitoring)"
echo "  - Error Reporting (for error tracking)"
echo "  - Monitoring Metrics (for custom metrics)"
echo "  - Secret Manager (scoped to ${SECRET_PREFIX}-* secrets)"
echo ""
echo "Deployment SAs have:"
echo "  - Cloud Run deployment permissions"
echo "  - Artifact Registry push (no delete in prod/stage)"
echo "  - Scoped service account usage"
echo ""
echo "When you need secrets later, create them with:"
echo "  gcloud secrets create ${SECRET_PREFIX}-<name> --project=<project-id>"
echo ""
echo "Examples:"
echo "  gcloud secrets create ${SECRET_PREFIX}-database-url --project=${PROJECT_PREFIX}-prod"
echo "  gcloud secrets create ${SECRET_PREFIX}-api-key --project=${PROJECT_PREFIX}-stage"
echo ""