#!/bin/bash
# GitOps Manifest Rollback Script
# Reverts GitOps repository to a previous working commit

set -e

# Configuration
GITOPS_REPO="${GITOPS_REPO:-}"
GITOPS_TOKEN="${GITOPS_TOKEN:-}"
GITOPS_BRANCH="${GITOPS_BRANCH:-main}"
GITOPS_PATH="${GITOPS_PATH:-k8s/overlays/prod}"
GITOPS_WORK_DIR="${GITOPS_WORK_DIR:-/tmp/gitops-rollback}"
TARGET_COMMIT="${TARGET_COMMIT:-}"
ROLLBACK_REASON="${ROLLBACK_REASON:-Error budget threshold breached}"

# Options
DRY_RUN="${DRY_RUN:-false}"
CREATE_PR="${CREATE_PR:-false}"
AUTO_MERGE="${AUTO_MERGE:-false}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/gitops-rollback.log}"

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

# Function to clone/update GitOps repo
setup_gitops_repo() {
    log "INFO" "Setting up GitOps repository"
    
    if [ ! -d "$GITOPS_WORK_DIR" ]; then
        log "INFO" "Cloning GitOps repository: $GITOPS_REPO"
        git clone -b "$GITOPS_BRANCH" \
            "https://${GITOPS_TOKEN}@github.com/${GITOPS_REPO}.git" \
            "$GITOPS_WORK_DIR" || {
            log "ERROR" "Failed to clone GitOps repository"
            return 1
        }
    else
        log "INFO" "Updating existing GitOps repository"
        cd "$GITOPS_WORK_DIR"
        git fetch origin
        git checkout "$GITOPS_BRANCH"
        git pull origin "$GITOPS_BRANCH"
    fi
    
    cd "$GITOPS_WORK_DIR"
    log "INFO" "GitOps repository ready at: $GITOPS_WORK_DIR"
    return 0
}

# Function to find previous working commit
find_previous_commit() {
    local current_commit="$1"
    local lookback_hours="${2:-24}"
    
    log "INFO" "Finding previous working commit (looking back ${lookback_hours}h)"
    
    cd "$GITOPS_WORK_DIR"
    
    # Get commit history
    local commits=$(git log --since="${lookback_hours} hours ago" \
        --oneline --all --format="%H %s" | \
        grep -v "$current_commit")
    
    if [ -z "$commits" ]; then
        log "WARN" "No commits found in last ${lookback_hours} hours"
        # Try looking back further
        commits=$(git log --since="7 days ago" \
            --oneline --all --format="%H %s" | \
            grep -v "$current_commit" | \
            head -5)
    fi
    
    # Select first commit (most recent)
    local previous_commit=$(echo "$commits" | head -1 | awk '{print $1}')
    
    if [ -z "$previous_commit" ]; then
        log "ERROR" "No previous commit found for rollback"
        return 1
    fi
    
    log "INFO" "Found previous commit: $previous_commit"
    echo "$previous_commit"
    return 0
}

# Function to verify commit exists
verify_commit() {
    local commit="$1"
    
    cd "$GITOPS_WORK_DIR"
    
    if git cat-file -e "$commit" 2>/dev/null; then
        log "INFO" "Commit $commit verified"
        return 0
    else
        log "ERROR" "Commit $commit does not exist"
        return 1
    fi
}

# Function to create rollback commit
create_rollback_commit() {
    local target_commit="$1"
    local reason="$2"
    
    log "INFO" "Creating rollback commit to: $target_commit"
    
    cd "$GITOPS_WORK_DIR"
    
    # Ensure we're on the target branch
    git checkout "$GITOPS_BRANCH"
    
    # Get files from target commit
    git checkout "$target_commit" -- "$GITOPS_PATH" || {
        log "ERROR" "Failed to checkout files from commit $target_commit"
        return 1
    }
    
    # Check if there are changes
    if git diff --quiet; then
        log "WARN" "No changes detected. Already at target commit or no differences."
        return 0
    fi
    
    # Stage changes
    git add "$GITOPS_PATH"
    
    # Create commit
    local commit_message="Rollback: $reason

Target commit: $target_commit
Rollback time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Triggered by: Error Budget Monitor

This is an automated rollback due to error budget threshold breach."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would create commit with message:"
        echo "$commit_message"
        git reset HEAD
        git checkout "$GITOPS_BRANCH" -- "$GITOPS_PATH"
        return 0
    fi
    
    git commit -m "$commit_message" || {
        log "ERROR" "Failed to create rollback commit"
        return 1
    }
    
    log "INFO" "Rollback commit created successfully"
    return 0
}

# Function to push rollback
push_rollback() {
    local create_pr="$1"
    
    cd "$GITOPS_WORK_DIR"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "WARN" "DRY RUN: Would push rollback to origin/$GITOPS_BRANCH"
        return 0
    fi
    
    if [ "$create_pr" = "true" ]; then
        # Create a branch for PR
        local rollback_branch="rollback/error-budget-$(date +%Y%m%d-%H%M%S)"
        git checkout -b "$rollback_branch"
        git push origin "$rollback_branch" || {
            log "ERROR" "Failed to push rollback branch"
            return 1
        }
        log "INFO" "Created rollback branch: $rollback_branch"
        log "INFO" "Please create a PR from $rollback_branch to $GITOPS_BRANCH"
    else
        # Direct push to main branch
        git push origin "$GITOPS_BRANCH" || {
            log "ERROR" "Failed to push rollback to $GITOPS_BRANCH"
            return 1
        }
        log "INFO" "Rollback pushed to $GITOPS_BRANCH"
    fi
    
    return 0
}

# Main rollback function
rollback() {
    log "INFO" "Starting GitOps manifest rollback"
    log "INFO" "Repository: $GITOPS_REPO"
    log "INFO" "Branch: $GITOPS_BRANCH"
    log "INFO" "Path: $GITOPS_PATH"
    
    # Setup repository
    setup_gitops_repo || return 1
    
    # Determine target commit
    local target_commit="$TARGET_COMMIT"
    
    if [ -z "$target_commit" ]; then
        local current_commit=$(git rev-parse HEAD)
        log "INFO" "Current commit: $current_commit"
        
        target_commit=$(find_previous_commit "$current_commit") || return 1
    fi
    
    # Verify commit
    verify_commit "$target_commit" || return 1
    
    # Create rollback commit
    create_rollback_commit "$target_commit" "$ROLLBACK_REASON" || return 1
    
    # Push rollback
    push_rollback "$CREATE_PR" || return 1
    
    log "INFO" "GitOps rollback completed successfully"
    log "INFO" "Rolled back to commit: $target_commit"
    
    return 0
}

# Main execution
main() {
    if [ -z "$GITOPS_REPO" ] || [ -z "$GITOPS_TOKEN" ]; then
        log "ERROR" "GITOPS_REPO and GITOPS_TOKEN must be set"
        exit 1
    fi
    
    rollback
    exit $?
}

main "$@"
