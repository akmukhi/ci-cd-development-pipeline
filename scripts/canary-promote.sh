#!/bin/bash
# Canary Deployment Promotion Script
# This script promotes a canary deployment to production

set -e

NAMESPACE="${NAMESPACE:-production}"
ROLLOUT_NAME="${ROLLOUT_NAME:-canary-app}"
ARGO_ROLLOUTS_VERSION="${ARGO_ROLLOUTS_VERSION:-v1.5.1}"

echo "🚀 Starting canary promotion process..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if kubectl-argo-rollouts plugin is available
if ! kubectl argo rollouts version &> /dev/null; then
    echo "⚠️  kubectl-argo-rollouts plugin not found. Installing..."
    curl -LO https://github.com/argoproj/argo-rollouts/releases/download/${ARGO_ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-amd64
    chmod +x kubectl-argo-rollouts-linux-amd64
    sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

# Get current rollout status
echo "📊 Current rollout status:"
kubectl argo rollouts get rollout ${ROLLOUT_NAME} -n ${NAMESPACE}

# Check if canary is healthy
echo "🔍 Checking canary health metrics..."
CANARY_STATUS=$(kubectl argo rollouts get rollout ${ROLLOUT_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}')

if [ "$CANARY_STATUS" != "Healthy" ] && [ "$CANARY_STATUS" != "Progressing" ]; then
    echo "❌ Canary is not in a healthy state. Current status: $CANARY_STATUS"
    echo "⚠️  Aborting promotion. Please investigate the canary deployment."
    exit 1
fi

# Prompt for confirmation
read -p "🤔 Do you want to promote the canary to 100%? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Promotion cancelled."
    exit 0
fi

# Promote canary
echo "⬆️  Promoting canary to 100%..."
kubectl argo rollouts promote ${ROLLOUT_NAME} -n ${NAMESPACE}

# Wait for rollout to complete
echo "⏳ Waiting for rollout to complete..."
kubectl argo rollouts status ${ROLLOUT_NAME} -n ${NAMESPACE} --watch

# Final status
echo "✅ Promotion complete!"
kubectl argo rollouts get rollout ${ROLLOUT_NAME} -n ${NAMESPACE}
