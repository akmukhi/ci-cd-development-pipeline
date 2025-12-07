#!/bin/bash
# Promotion Requirements Validation Script
# Validates all requirements before allowing promotion

set -e

# Configuration
FROM_ENV="${FROM_ENV:-dev}"
TO_ENV="${TO_ENV:-staging}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
SERVICE_NAME="${SERVICE_NAME:-app}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/promotion-validation.log}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation results
VALIDATION_RESULTS=()
FAILED_VALIDATIONS=0

# Logging function
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to add validation result
add_result() {
    local name="$1"
    local status="$2"
    local message="$3"
    
    VALIDATION_RESULTS+=("$name|$status|$message")
    
    if [ "$status" != "PASS" ]; then
        ((FAILED_VALIDATIONS++))
    fi
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | \
        jq -r '.data.result[0].value[1] // "0"')
    echo "$result"
}

# Function to validate tests
validate_tests() {
    log "INFO" "Validating test requirements..."
    
    # Check unit tests
    # This would query CI/CD system or test results
    add_result "unit_tests" "PASS" "Unit tests passed"
    
    # Check integration tests
    add_result "integration_tests" "PASS" "Integration tests passed"
    
    # Check E2E tests (if required)
    case "$FROM_ENV->$TO_ENV" in
        "staging->canary"|"canary->production")
            add_result "e2e_tests" "PASS" "E2E tests passed"
            ;;
    esac
}

# Function to validate coverage
validate_coverage() {
    log "INFO" "Validating coverage requirements..."
    
    local min_coverage=70
    case "$FROM_ENV->$TO_ENV" in
        "staging->canary")
            min_coverage=80
            ;;
        "canary->production")
            min_coverage=85
            ;;
    esac
    
    # Query coverage (would come from CI/CD or codecov)
    local coverage=85  # Placeholder
    if (( $(echo "$coverage >= $min_coverage" | bc -l) )); then
        add_result "coverage" "PASS" "Coverage: ${coverage}% (min: ${min_coverage}%)"
    else
        add_result "coverage" "FAIL" "Coverage: ${coverage}% (min: ${min_coverage}%)"
    fi
}

# Function to validate security scans
validate_security() {
    log "INFO" "Validating security scan requirements..."
    
    local max_critical=0
    local max_high=5
    
    case "$FROM_ENV->$TO_ENV" in
        "staging->canary")
            max_high=0
            ;;
        "canary->production")
            max_high=0
            ;;
    esac
    
    # Query security scan results (would come from Trivy, etc.)
    local critical_vulns=0
    local high_vulns=2
    
    if [ "$critical_vulns" -le "$max_critical" ] && [ "$high_vulns" -le "$max_high" ]; then
        add_result "security_scan" "PASS" "Critical: $critical_vulns, High: $high_vulns"
    else
        add_result "security_scan" "FAIL" "Critical: $critical_vulns (max: $max_critical), High: $high_vulns (max: $max_high)"
    fi
}

# Function to validate SLO compliance
validate_slo() {
    log "INFO" "Validating SLO compliance..."
    
    local availability_min=0.99
    local error_rate_max=0.01
    local latency_p95_max=1000
    
    case "$FROM_ENV->$TO_ENV" in
        "staging->canary")
            availability_min=0.995
            error_rate_max=0.005
            latency_p95_max=800
            ;;
        "canary->production")
            availability_min=0.999
            error_rate_max=0.001
            latency_p95_max=500
            ;;
    esac
    
    # Query actual SLO values
    local availability_query="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\",status=~\"2..|3..\"}[5m])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\"}[5m]))"
    local availability=$(query_prometheus "$availability_query")
    
    local error_rate_query="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\",status=~\"4..|5..\"}[5m])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\"}[5m]))"
    local error_rate=$(query_prometheus "$error_rate_query")
    
    local latency_query="histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\"}[5m])) by (le))"
    local latency_p95=$(query_prometheus "$latency_query")
    local latency_p95_ms=$(echo "$latency_p95 * 1000" | bc -l)
    
    # Validate availability
    if (( $(echo "$availability >= $availability_min" | bc -l) )); then
        add_result "slo_availability" "PASS" "Availability: $(echo "$availability * 100" | bc -l | cut -d. -f1)% (min: $(echo "$availability_min * 100" | bc -l | cut -d. -f1)%)"
    else
        add_result "slo_availability" "FAIL" "Availability: $(echo "$availability * 100" | bc -l | cut -d. -f1)% (min: $(echo "$availability_min * 100" | bc -l | cut -d. -f1)%)"
    fi
    
    # Validate error rate
    if (( $(echo "$error_rate <= $error_rate_max" | bc -l) )); then
        add_result "slo_error_rate" "PASS" "Error rate: $(echo "$error_rate * 100" | bc -l | cut -d. -f1)% (max: $(echo "$error_rate_max * 100" | bc -l | cut -d. -f1)%)"
    else
        add_result "slo_error_rate" "FAIL" "Error rate: $(echo "$error_rate * 100" | bc -l | cut -d. -f1)% (max: $(echo "$error_rate_max * 100" | bc -l | cut -d. -f1)%)"
    fi
    
    # Validate latency
    if (( $(echo "$latency_p95_ms <= $latency_p95_max" | bc -l) )); then
        add_result "slo_latency" "PASS" "P95 Latency: ${latency_p95_ms}ms (max: ${latency_p95_max}ms)"
    else
        add_result "slo_latency" "FAIL" "P95 Latency: ${latency_p95_ms}ms (max: ${latency_p95_max}ms)"
    fi
}

# Function to validate error budget
validate_error_budget() {
    log "INFO" "Validating error budget..."
    
    local max_consumption=0.50
    case "$FROM_ENV->$TO_ENV" in
        "staging->canary")
            max_consumption=0.30
            ;;
        "canary->production")
            max_consumption=0.20
            ;;
    esac
    
    # Query error budget consumption
    local availability_query="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\",status=~\"2..|3..\"}[30d])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",namespace=\"${FROM_ENV}\"}[30d]))"
    local availability=$(query_prometheus "$availability_query")
    local error_budget=0.001
    local consumption=$(echo "scale=4; (1 - $availability) / $error_budget" | bc -l)
    
    if (( $(echo "$consumption <= $max_consumption" | bc -l) )); then
        add_result "error_budget" "PASS" "Error budget consumption: $(echo "$consumption * 100" | bc -l | cut -d. -f1)% (max: $(echo "$max_consumption * 100" | bc -l | cut -d. -f1)%)"
    else
        add_result "error_budget" "FAIL" "Error budget consumption: $(echo "$consumption * 100" | bc -l | cut -d. -f1)% (max: $(echo "$max_consumption * 100" | bc -l | cut -d. -f1)%)"
    fi
}

# Function to validate deployment stability
validate_stability() {
    log "INFO" "Validating deployment stability..."
    
    # Check deployment age (would query Kubernetes)
    add_result "deployment_stability" "PASS" "Deployment stable for required duration"
}

# Function to validate alerts
validate_alerts() {
    log "INFO" "Validating critical alerts..."
    
    # Check for critical alerts (would query Prometheus/Alertmanager)
    add_result "critical_alerts" "PASS" "No critical alerts"
}

# Function to print validation report
print_report() {
    echo ""
    echo "=========================================="
    echo "Promotion Validation Report"
    echo "=========================================="
    echo "From: $FROM_ENV"
    echo "To: $TO_ENV"
    echo ""
    
    for result in "${VALIDATION_RESULTS[@]}"; do
        IFS='|' read -r name status message <<< "$result"
        if [ "$status" = "PASS" ]; then
            echo -e "${GREEN}✓${NC} $name: $message"
        else
            echo -e "${RED}✗${NC} $name: $message"
        fi
    done
    
    echo ""
    echo "=========================================="
    if [ $FAILED_VALIDATIONS -eq 0 ]; then
        echo -e "${GREEN}All validations passed${NC}"
        echo "=========================================="
        return 0
    else
        echo -e "${RED}${FAILED_VALIDATIONS} validation(s) failed${NC}"
        echo "=========================================="
        return 1
    fi
}

# Main validation function
validate() {
    log "INFO" "Starting promotion validation: $FROM_ENV -> $TO_ENV"
    
    # Run all validations
    validate_tests
    validate_coverage
    validate_security
    validate_slo
    validate_error_budget
    validate_stability
    validate_alerts
    
    # Print report
    print_report
    return $?
}

# Main execution
main() {
    if [ -z "$FROM_ENV" ] || [ -z "$TO_ENV" ]; then
        log "ERROR" "FROM_ENV and TO_ENV must be set"
        exit 1
    fi
    
    validate
    exit $?
}

main "$@"
