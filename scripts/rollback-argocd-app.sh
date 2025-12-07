#!/bin/bash
# ArgoCD Application Rollback Script
# Rolls back ArgoCD application to a previous revision

set -e

# Configuration
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd-server.argocd.svc.cluster.local:443}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-app-prod}"
ARGOCD_USERNAME="${ARGOCD_USERNAME:-admin}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}"
ARGOCD_INSECURE="${ARGOCD_INSECURE:-true}"

# Rollback options
TARGET_REVISION="${TARGET_REVISION:-}"
ROLLBACK_REASON="${ROLLBACK_REASON:-Error budget threshold breached}"
AUTO_SYNC="${AUTO_SYNC:-true}"

# Options
DRY_RUN="${DRY_RUN:-false}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/argocd-rollback.log}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to check if argocd CLI is available
check_argocd_cli() {
    if ! command -v argocd &> /dev/null; then
        log "ERROR" "argocd CLI not found. Please install it first."
        log "INFO" "Install: curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
        return 1
    fi
    return 0
}

# Function to login to ArgoCD
login_argocd() {
    log "INFO" "Logging in to ArgoCD: $ARGOCD_SERVER"
    
    local insecure_flag=""
    if [ "$ARGOCD_INSECURE" = "true" ]; then
        insecure_flag="--insecure"
    fi
    
    argocd login "$ARGOCD_SERVER" \
        --username "$ARGOCD_USERNAME" \
        --password "$ARGOCD_PASSWORD" \
        $insecure_flag || {
        log "ERROR" "Failed to login to ArgoCD"
        return 1
    }
    
    log "INFO" "Successfully logged in to ArgoCD"
    return 0
}

# Function to get application history
get_app_history() {
    log "INFO" "Getting application history for: $ARGOCD_APP_NAME"
    
    local history=$(argocd app history "$ARGOCD_APP_NAME" --output json) || {
        log "ERROR" "Failed to get application history"
        return 1
    }
    
    echo "$history"
    return 0
}

# Function to find previous healthy revision
find_previous_revision() {
    local history="$1"
    
    log "INFO" "Finding previous healthy revision"
    
    # Get revisions, excluding current
    local revisions=$(echo "$history" | jq -r '.[1:] | .[] | "\(.id)|\(.deployedAt)|\(.healthStatus)"')
    
    if [ -z "$revisions" ]; then
        log "ERROR" "No previous revisions found"
        return 1
    fi
    
    # Find first healthy revision
    local previous_revision=""
    while IFS='|' read -r id deployed_at health; do
        if [ "$health" = "Healthy" ]; then
            previous_revision="$id"
            log "INFO" "Found healthy revision: $previous_revision (deployed: $deployed_at)"
            break
        fi
    done <<< "$revisions"
    
    if [ -z "$previous_revision" ]; then
        # Fallback to most recent previous revision
        previous_revision=$(echo "$history" | jq -r '.[1].id // empty')
        if [ -z "$previous_revision" ]; then
            log "ERROR" "No previous revision found"
            return 1
        fi
        log "WARN" "No healthy revision found, using most recent: $previous_revision"
    fi
    
    echo "$previous_revision"
    return 0
}

# Function to get application status
get_app_status() {
    local status=$(argocd app get "$ARGOCD_APP_NAME" --output json) || {
        log "ERROR" "Failed to get application status"
        return 1
    }
    
    echo "$status"
    return 0
}

# Function to rollback application
rollback_app() {
    local target_revision="$1"
    local reason="$2"
    
    log "INFO" "Rolling back application to revision: $target_revision"
    log "INFO" "Reason: $reason"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would rollback to revision $target_revision"
        return 0
    fi
    
    # Perform rollback
    argocd app rollback "$ARGOCD_APP_NAME" "$target_revision" || {
        log "ERROR" "Failed to rollback application"
        return 1
    }
    
    log "INFO" "Rollback initiated successfully"
    
    # Wait for sync if auto-sync is enabled
    if [ "$AUTO_SYNC" = "true" ]; then
        log "INFO" "Waiting for application to sync..."
        argocd app wait "$ARGOCD_APP_NAME" --timeout 300 || {
            log "WARN" "Application sync timeout or failed"
        }
    fi
    
    # Get final status
    local final_status=$(get_app_status)
    local health=$(echo "$final_status" | jq -r '.status.health.status')
    local sync=$(echo "$final_status" | jq -r '.status.sync.status')
    
    log "INFO" "Rollback completed. Health: $health, Sync: $sync"
    
    if [ "$health" != "Healthy" ] || [ "$sync" != "Synced" ]; then
        log "WARN" "Application is not in healthy/synced state after rollback"
        return 1
    fi
    
    return 0
}

# Main rollback function
rollback() {
    log "INFO" "Starting ArgoCD application rollback"
    log "INFO" "Application: $ARGOCD_APP_NAME"
    log "INFO" "Server: $ARGOCD_SERVER"
    
    # Check prerequisites
    check_argocd_cli || return 1
    
    # Login
    login_argocd || return 1
    
    # Get application history
    local history=$(get_app_history) || return 1
    
    # Determine target revision
    local target_revision="$TARGET_REVISION"
    
    if [ -z "$target_revision" ]; then
        target_revision=$(find_previous_revision "$history") || return 1
    fi
    
    # Get current status
    local current_status=$(get_app_status)
    local current_revision=$(echo "$current_status" | jq -r '.status.sync.revision')
    log "INFO" "Current revision: $current_revision"
    
    if [ "$current_revision" = "$target_revision" ]; then
        log "WARN" "Already at target revision. No rollback needed."
        return 0
    fi
    
    # Perform rollback
    rollback_app "$target_revision" "$ROLLBACK_REASON" || return 1
    
    log "INFO" "ArgoCD rollback completed successfully"
    return 0
}

# Main execution
main() {
    if [ -z "$ARGOCD_SERVER" ] || [ -z "$ARGOCD_APP_NAME" ]; then
        log "ERROR" "ARGOCD_SERVER and ARGOCD_APP_NAME must be set"
        exit 1
    fi
    
    if [ -z "$ARGOCD_PASSWORD" ]; then
        log "ERROR" "ARGOCD_PASSWORD must be set"
        exit 1
    fi
    
    rollback
    exit $?
}

main "$@"
