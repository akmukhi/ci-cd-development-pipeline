#!/bin/bash
# Automated Rollback on Error Budget Threshold Breach
# Monitors error budget and automatically rolls back GitOps manifests when thresholds are exceeded

set -e

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
SERVICE_NAME="${SERVICE_NAME:-app}"
NAMESPACE="${NAMESPACE:-production}"
SLO_WINDOW="${SLO_WINDOW:-30d}"
ERROR_BUDGET="${ERROR_BUDGET:-0.001}"

# Rollback thresholds
WARNING_THRESHOLD=0.50
CRITICAL_THRESHOLD=0.80
EMERGENCY_THRESHOLD=0.95

# GitOps configuration
GITOPS_REPO="${GITOPS_REPO:-}"
GITOPS_TOKEN="${GITOPS_TOKEN:-}"
GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
GITOPS_PATH="${GITOPS_PATH:-k8s/overlays/prod}"
GITOPS_WORK_DIR="${GITOPS_WORK_DIR:-/tmp/gitops-rollback}"

# ArgoCD configuration
ARGOCD_SERVER="${ARGOCD_SERVER:-argocd-server.argocd.svc.cluster.local:443}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-app-prod}"
ARGOCD_USERNAME="${ARGOCD_USERNAME:-admin}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}"

# Rollback policy
ROLLBACK_ENABLED="${ROLLBACK_ENABLED:-true}"
AUTO_ROLLBACK_CRITICAL="${AUTO_ROLLBACK_CRITICAL:-true}"
AUTO_ROLLBACK_EMERGENCY="${AUTO_ROLLBACK_EMERGENCY:-true}"
REQUIRE_APPROVAL="${REQUIRE_APPROVAL:-false}"

# Notification
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
PAGERDUTY_KEY="${PAGERDUTY_KEY:-}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/error-budget-rollback.log}"
DRY_RUN="${DRY_RUN:-false}"

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

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | \
        jq -r '.data.result[0].value[1] // "0"')
    echo "$result"
}

# Function to send Slack notification
notify_slack() {
    local message="$1"
    local severity="${2:-info}"
    
    if [ -z "$SLACK_WEBHOOK" ]; then
        return
    fi
    
    local color="good"
    case "$severity" in
        critical) color="danger" ;;
        warning) color="warning" ;;
    esac
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{
            \"attachments\": [{
                \"color\": \"$color\",
                \"title\": \"Error Budget Rollback Alert\",
                \"text\": \"$message\",
                \"footer\": \"Error Budget Monitor\",
                \"ts\": $(date +%s)
            }]
        }" \
        "$SLACK_WEBHOOK" 2>/dev/null || true
}

# Function to trigger PagerDuty alert
notify_pagerduty() {
    local message="$1"
    local severity="${2:-critical}"
    
    if [ -z "$PAGERDUTY_KEY" ]; then
        return
    fi
    
    curl -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Token token=$PAGERDUTY_KEY" \
        -d "{
            \"routing_key\": \"$PAGERDUTY_KEY\",
            \"event_action\": \"trigger\",
            \"payload\": {
                \"summary\": \"$message\",
                \"severity\": \"$severity\",
                \"source\": \"Error Budget Monitor\",
                \"custom_details\": {
                    \"service\": \"$SERVICE_NAME\",
                    \"namespace\": \"$NAMESPACE\"
                }
            }
        }" \
        https://events.pagerduty.com/v2/enqueue 2>/dev/null || true
}

# Function to get current Git commit
get_current_commit() {
    local repo_path="$1"
    cd "$repo_path"
    git rev-parse HEAD
}

# Function to get previous working commit
get_previous_commit() {
    local repo_path="$1"
    local current_commit="$2"
    
    cd "$repo_path"
    # Get commits from last 24 hours, excluding current
    git log --since="24 hours ago" --oneline --all | \
        grep -v "$current_commit" | \
        head -1 | \
        awk '{print $1}'
}

# Function to rollback GitOps manifest
rollback_gitops() {
    local target_commit="$1"
    local reason="$2"
    
    log "INFO" "Starting GitOps rollback to commit: $target_commit"
    log "INFO" "Reason: $reason"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would rollback to commit $target_commit"
        return 0
    fi
    
    # Clone or update GitOps repo
    if [ ! -d "$GITOPS_WORK_DIR" ]; then
        git clone -b "$GITOPS_BRANCH" \
            "https://${GITOPS_TOKEN}@github.com/${GITOPS_REPO}.git" \
            "$GITOPS_WORK_DIR" || {
            log "ERROR" "Failed to clone GitOps repository"
            return 1
        }
    else
        cd "$GITOPS_WORK_DIR"
        git fetch origin
        git checkout "$GITOPS_BRANCH"
        git pull origin "$GITOPS_BRANCH"
    fi
    
    cd "$GITOPS_WORK_DIR"
    
    # Checkout target commit
    git checkout "$target_commit" || {
        log "ERROR" "Failed to checkout commit $target_commit"
        return 1
    }
    
    # Create rollback branch
    local rollback_branch="rollback/error-budget-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$rollback_branch"
    
    # Merge rollback into main branch
    git checkout "$GITOPS_BRANCH"
    git merge "$rollback_branch" -m "Rollback: Error budget threshold breached - $reason"
    
    # Push to GitOps repo
    git push origin "$GITOPS_BRANCH" || {
        log "ERROR" "Failed to push rollback to GitOps repository"
        return 1
    }
    
    log "INFO" "Successfully rolled back GitOps manifest to commit $target_commit"
    return 0
}

# Function to rollback ArgoCD application
rollback_argocd() {
    local revision="$1"
    local reason="$2"
    
    log "INFO" "Starting ArgoCD rollback to revision: $revision"
    log "INFO" "Reason: $reason"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would rollback ArgoCD app to revision $revision"
        return 0
    fi
    
    # Login to ArgoCD
    argocd login "$ARGOCD_SERVER" \
        --username "$ARGOCD_USERNAME" \
        --password "$ARGOCD_PASSWORD" \
        --insecure || {
        log "ERROR" "Failed to login to ArgoCD"
        return 1
    }
    
    # Get application history
    local history=$(argocd app history "$ARGOCD_APP_NAME" --output json)
    local previous_revision=$(echo "$history" | jq -r '.[1].id // empty')
    
    if [ -z "$previous_revision" ]; then
        log "ERROR" "No previous revision found for rollback"
        return 1
    fi
    
    # Rollback to previous revision
    argocd app rollback "$ARGOCD_APP_NAME" "$previous_revision" || {
        log "ERROR" "Failed to rollback ArgoCD application"
        return 1
    }
    
    log "INFO" "Successfully rolled back ArgoCD application to revision $previous_revision"
    return 0
}

# Function to check if rollback is needed
check_and_rollback() {
    # Calculate availability
    local availability_query="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
    local availability=$(query_prometheus "$availability_query")
    
    # Calculate error budget consumption
    local error_budget_consumed=$(echo "scale=4; (1 - $availability) / $ERROR_BUDGET" | bc -l)
    local error_budget_pct=$(echo "$error_budget_consumed * 100" | bc -l)
    
    log "INFO" "Error budget consumption: ${error_budget_pct}%"
    
    # Determine action based on threshold
    local should_rollback=false
    local rollback_reason=""
    local severity=""
    
    if (( $(echo "$error_budget_consumed >= $EMERGENCY_THRESHOLD" | bc -l) )); then
        should_rollback=true
        rollback_reason="Emergency: Error budget ${error_budget_pct}% consumed (threshold: 95%)"
        severity="critical"
        
        if [ "$AUTO_ROLLBACK_EMERGENCY" != "true" ]; then
            log "WARN" "Emergency threshold reached but auto-rollback disabled"
            should_rollback=false
        fi
        
    elif (( $(echo "$error_budget_consumed >= $CRITICAL_THRESHOLD" | bc -l) )); then
        should_rollback=true
        rollback_reason="Critical: Error budget ${error_budget_pct}% consumed (threshold: 80%)"
        severity="critical"
        
        if [ "$AUTO_ROLLBACK_CRITICAL" != "true" ]; then
            log "WARN" "Critical threshold reached but auto-rollback disabled"
            should_rollback=false
        fi
        
    elif (( $(echo "$error_budget_consumed >= $WARNING_THRESHOLD" | bc -l) )); then
        log "WARN" "Warning threshold reached: ${error_budget_pct}% (no rollback, monitoring only)"
        notify_slack "Error budget ${error_budget_pct}% consumed. Monitoring closely." "warning"
        return 0
    else
        log "INFO" "Error budget within acceptable limits: ${error_budget_pct}%"
        return 0
    fi
    
    # Check if rollback is enabled
    if [ "$ROLLBACK_ENABLED" != "true" ]; then
        log "WARN" "Rollback disabled. Threshold breached but no action taken."
        notify_slack "Error budget threshold breached but rollback is disabled" "$severity"
        return 0
    fi
    
    # Require approval if configured
    if [ "$REQUIRE_APPROVAL" = "true" ] && [ "$DRY_RUN" != "true" ]; then
        log "WARN" "Approval required for rollback. Skipping automatic rollback."
        notify_slack "Rollback approval required for: $rollback_reason" "$severity"
        notify_pagerduty "Rollback approval required: $rollback_reason" "$severity"
        return 0
    fi
    
    # Perform rollback
    log "WARN" "$rollback_reason"
    notify_slack "$rollback_reason - Initiating rollback" "$severity"
    notify_pagerduty "$rollback_reason - Rollback initiated" "$severity"
    
    # Rollback GitOps if configured
    if [ -n "$GITOPS_REPO" ] && [ -n "$GITOPS_TOKEN" ]; then
        local current_commit=$(get_current_commit "$GITOPS_WORK_DIR" 2>/dev/null || echo "")
        local previous_commit=$(get_previous_commit "$GITOPS_WORK_DIR" "$current_commit" 2>/dev/null || echo "")
        
        if [ -n "$previous_commit" ]; then
            rollback_gitops "$previous_commit" "$rollback_reason" || {
                log "ERROR" "GitOps rollback failed"
                notify_slack "GitOps rollback failed: $rollback_reason" "critical"
                return 1
            }
        else
            log "WARN" "No previous commit found for GitOps rollback"
        fi
    fi
    
    # Rollback ArgoCD if configured
    if [ -n "$ARGOCD_SERVER" ] && [ -n "$ARGOCD_APP_NAME" ]; then
        rollback_argocd "previous" "$rollback_reason" || {
            log "ERROR" "ArgoCD rollback failed"
            notify_slack "ArgoCD rollback failed: $rollback_reason" "critical"
            return 1
        }
    fi
    
    # Success notification
    notify_slack "Rollback completed successfully: $rollback_reason" "info"
    log "INFO" "Rollback completed successfully"
    
    return 0
}

# Main execution
main() {
    log "INFO" "Starting error budget monitoring and rollback check"
    log "INFO" "Service: $SERVICE_NAME, Namespace: $NAMESPACE"
    
    # Check prerequisites
    if [ "$ROLLBACK_ENABLED" = "true" ]; then
        if [ -z "$GITOPS_REPO" ] && [ -z "$ARGOCD_SERVER" ]; then
            log "ERROR" "Rollback enabled but no GitOps repo or ArgoCD server configured"
            exit 1
        fi
    fi
    
    # Check Prometheus connectivity
    if ! curl -s "${PROMETHEUS_URL}/api/v1/status/config" > /dev/null; then
        log "ERROR" "Cannot connect to Prometheus at $PROMETHEUS_URL"
        exit 1
    fi
    
    # Perform check and rollback if needed
    check_and_rollback
    
    log "INFO" "Error budget monitoring check completed"
}

# Run main function
main "$@"
