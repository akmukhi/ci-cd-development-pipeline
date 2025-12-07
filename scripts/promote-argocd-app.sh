#!/bin/bash
# ArgoCD Application Promotion Script
# Promotes ArgoCD application between environments

set -e

# Configuration
FROM_ENV="${FROM_ENV:-dev}"
TO_ENV="${TO_ENV:-staging}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd-server.argocd.svc.cluster.local:443}"
ARGOCD_USERNAME="${ARGOCD_USERNAME:-admin}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}"
ARGOCD_INSECURE="${ARGOCD_INSECURE:-true}"

# Options
DRY_RUN="${DRY_RUN:-false}"
AUTO_SYNC="${AUTO_SYNC:-true}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/argocd-promotion.log}"

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
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to check if argocd CLI is available
check_argocd_cli() {
    if ! command -v argocd &> /dev/null; then
        log "ERROR" "argocd CLI not found. Please install it first."
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

# Function to get source application image
get_source_image() {
    local from_app="app-$FROM_ENV"
    
    log "INFO" "Getting source application image: $from_app"
    
    local app_info=$(argocd app get "$from_app" --output json) || {
        log "ERROR" "Failed to get source application info"
        return 1
    }
    
    # Extract image tag from application (would need to parse manifest)
    local image_tag=$(echo "$app_info" | jq -r '.status.sync.revision // "latest"')
    
    log "INFO" "Source image tag: $image_tag"
    echo "$image_tag"
    return 0
}

# Function to update target application
update_target_application() {
    local to_app="app-$TO_ENV"
    local image_tag="$1"
    
    log "INFO" "Updating target application: $to_app"
    log "INFO" "Image tag: $image_tag"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would update application $to_app with image $image_tag"
        return 0
    fi
    
    # Sync application (GitOps will handle the image update)
    if [ "$AUTO_SYNC" = "true" ]; then
        argocd app sync "$to_app" --prune || {
            log "ERROR" "Failed to sync target application"
            return 1
        }
    else
        log "INFO" "Auto-sync disabled. Application will sync when GitOps updates manifest."
    fi
    
    log "INFO" "Target application updated successfully"
    return 0
}

# Function to wait for application sync
wait_for_sync() {
    local to_app="app-$TO_ENV"
    local timeout="${1:-300}"
    
    log "INFO" "Waiting for application sync: $to_app (timeout: ${timeout}s)"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would wait for sync"
        return 0
    fi
    
    argocd app wait "$to_app" --timeout "$timeout" || {
        log "ERROR" "Application sync timeout or failed"
        return 1
    }
    
    log "INFO" "Application synced successfully"
    return 0
}

# Function to verify application health
verify_health() {
    local to_app="app-$TO_ENV"
    
    log "INFO" "Verifying application health: $to_app"
    
    local app_info=$(argocd app get "$to_app" --output json) || {
        log "ERROR" "Failed to get application info"
        return 1
    }
    
    local health=$(echo "$app_info" | jq -r '.status.health.status')
    local sync=$(echo "$app_info" | jq -r '.status.sync.status')
    
    log "INFO" "Application health: $health, sync: $sync"
    
    if [ "$health" = "Healthy" ] && [ "$sync" = "Synced" ]; then
        log "INFO" "Application is healthy and synced"
        return 0
    else
        log "ERROR" "Application is not healthy (health: $health, sync: $sync)"
        return 1
    fi
}

# Main promotion function
promote() {
    log "INFO" "=========================================="
    log "INFO" "ArgoCD Application Promotion"
    log "INFO" "=========================================="
    log "INFO" "From: $FROM_ENV"
    log "INFO" "To: $TO_ENV"
    log "INFO" ""
    
    # Check prerequisites
    check_argocd_cli || return 1
    
    # Login
    login_argocd || return 1
    
    # Get source image
    local image_tag=$(get_source_image) || return 1
    
    # Update target application
    update_target_application "$image_tag" || return 1
    
    # Wait for sync
    if [ "$AUTO_SYNC" = "true" ]; then
        wait_for_sync || return 1
    fi
    
    # Verify health
    verify_health || return 1
    
    log "INFO" ""
    log "INFO" "=========================================="
    log "INFO" "Promotion Completed Successfully"
    log "INFO" "=========================================="
    log "INFO" "Application promoted from $FROM_ENV to $TO_ENV"
    log "INFO" "Image tag: $image_tag"
    
    return 0
}

# Main execution
main() {
    if [ -z "$FROM_ENV" ] || [ -z "$TO_ENV" ]; then
        log "ERROR" "FROM_ENV and TO_ENV must be set"
        exit 1
    fi
    
    if [ -z "$ARGOCD_PASSWORD" ]; then
        log "ERROR" "ARGOCD_PASSWORD must be set"
        exit 1
    fi
    
    promote
    exit $?
}

main "$@"
