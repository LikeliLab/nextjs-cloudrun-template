#!/bin/bash
set +e  # Don't exit on errors

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/load_env.sh"
load_env

for ENV in $PROJECT_ENVS; do
  POOL_NAME="github-pool-${ENV}"
  PROVIDER_NAME="github-provider-${ENV}"
  
  # Final verification
  echo ""
  echo "Final verification..."
  sleep 5
  
  FINAL_CONDITION=$(gcloud iam workload-identity-pools providers describe "${PROVIDER_NAME}" \
    --project="${WIF_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${POOL_NAME}" \
    --format="value(attributeCondition)" 2>/dev/null)
  
  echo "Final condition:"
  echo "  ${FINAL_CONDITION}"
  echo ""
  
  if [ "$FINAL_CONDITION" = "$CONDITION" ]; then
    echo "✅✅✅ SUCCESS - Condition is correct!"
  else
    echo "❌ FAILED - Condition still doesn't match"
    echo "Expected: ${CONDITION}"
    echo "Got:      ${FINAL_CONDITION}"
  fi
  
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Script complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"