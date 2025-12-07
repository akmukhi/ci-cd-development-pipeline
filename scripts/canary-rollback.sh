#!/bin/bash
# Canary Deployment Rollback Script
# This script rolls back a canary deployment if issues are detected

set -e

NAMESPACE="${NAMESPACE:-production}"
ROLLOUT_NAME="${ROLLOUT_NAME:-canary-app}"
ARGO_ROLLOUTS_VERSION="${ARGO_ROLLOUTS_VERSION:-v1.5.1}"

echo "⏪ Starting canary rollback process..."

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

# Get revision history
echo "📜 Rollout revision history:"
kubectl argo rollouts history ${ROLLOUT_NAME} -n ${NAMESPACE}

# Prompt for confirmation
read -p "⚠️  Do you want to rollback the canary deployment? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Rollback cancelled."
    exit 0
fi

# Rollback to previous revision
echo "⏪ Rolling back to previous revision..."
kubectl argo rollouts undo ${ROLLOUT_NAME} -n ${NAMESPACE}

# Wait for rollback to complete
echo "⏳ Waiting for rollback to complete..."
kubectl argo rollouts status ${ROLLOUT_NAME} -n ${NAMESPACE} --watch

# Final status
echo "✅ Rollback complete!"
kubectl argo rollouts get rollout ${ROLLOUT_NAME} -n ${NAMESPACE}
