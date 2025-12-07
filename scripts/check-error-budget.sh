#!/bin/bash
# Error Budget Checking Script
# Monitors error budget consumption and triggers alerts/actions

set -e

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
SERVICE_NAME="${SERVICE_NAME:-app}"
NAMESPACE="${NAMESPACE:-production}"
SLO_WINDOW="${SLO_WINDOW:-30d}"
ERROR_BUDGET="${ERROR_BUDGET:-0.001}"

# Thresholds
WARNING_THRESHOLD=0.50
CRITICAL_THRESHOLD=0.80
EMERGENCY_THRESHOLD=0.95

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | \
        jq -r '.data.result[0].value[1]')
    echo "$result"
}

# Function to format percentage
format_percentage() {
    local value="$1"
    printf "%.2f%%" $(echo "$value * 100" | bc -l)
}

# Function to calculate time until budget exhaustion
calculate_time_until_exhaustion() {
    local burn_rate="$1"
    local remaining_budget="$2"
    
    if (( $(echo "$burn_rate <= 0" | bc -l) )); then
        echo "N/A (no burn)"
        return
    fi
    
    # Time in hours = remaining_budget / (burn_rate * error_budget_per_hour)
    # Assuming error budget is for 30 days = 720 hours
    local budget_per_hour=$(echo "scale=6; $ERROR_BUDGET / 720" | bc -l)
    local hours_remaining=$(echo "scale=2; $remaining_budget / ($burn_rate * $budget_per_hour)" | bc -l)
    
    if (( $(echo "$hours_remaining < 1" | bc -l) )); then
        local minutes=$(echo "$hours_remaining * 60" | bc -l | cut -d. -f1)
        echo "${minutes}m"
    elif (( $(echo "$hours_remaining < 24" | bc -l) )); then
        echo "${hours_remaining}h"
    else
        local days=$(echo "scale=1; $hours_remaining / 24" | bc -l)
        echo "${days}d"
    fi
}

echo "=========================================="
echo "Error Budget Monitor"
echo "=========================================="
echo "Service: ${SERVICE_NAME}"
echo "Window: ${SLO_WINDOW}"
echo "Error Budget: $(format_percentage $ERROR_BUDGET)"
echo ""

# Calculate availability
AVAILABILITY_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
AVAILABILITY=$(query_prometheus "$AVAILABILITY_QUERY")

# Calculate error budget consumption
ERROR_BUDGET_CONSUMED=$(echo "scale=4; (1 - $AVAILABILITY) / $ERROR_BUDGET" | bc -l)
ERROR_BUDGET_REMAINING=$(echo "scale=4; 1 - $ERROR_BUDGET_CONSUMED" | bc -l)

# Calculate burn rates
BURN_RATE_6H_QUERY="(1 - (sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[6h])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[6h])))) / $ERROR_BUDGET"
BURN_RATE_6H=$(query_prometheus "$BURN_RATE_6H_QUERY")

BURN_RATE_1H_QUERY="(1 - (sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[1h])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[1h])))) / $ERROR_BUDGET"
BURN_RATE_1H=$(query_prometheus "$BURN_RATE_1H_QUERY")

# Display results
echo "📊 Current Status:"
echo "  Availability: $(format_percentage $AVAILABILITY)"
echo "  Error Budget Consumed: $(format_percentage $ERROR_BUDGET_CONSUMED)"
echo "  Error Budget Remaining: $(format_percentage $ERROR_BUDGET_REMAINING)"
echo ""
echo "🔥 Burn Rates:"
echo "  1h Burn Rate: ${BURN_RATE_1H}x"
echo "  6h Burn Rate: ${BURN_RATE_6H}x"

# Calculate time until exhaustion
TIME_UNTIL_EXHAUSTION=$(calculate_time_until_exhaustion "$BURN_RATE_6H" "$ERROR_BUDGET_REMAINING")
echo "  Estimated time until exhaustion: ${TIME_UNTIL_EXHAUSTION}"
echo ""

# Determine status and actions
STATUS="OK"
SEVERITY="info"
ACTIONS=()

if (( $(echo "$ERROR_BUDGET_CONSUMED >= $EMERGENCY_THRESHOLD" | bc -l) )); then
    STATUS="EMERGENCY"
    SEVERITY="critical"
    echo -e "${RED}🚨 EMERGENCY: Error budget ${EMERGENCY_THRESHOLD}% consumed!${NC}"
    ACTIONS+=("Freeze all deployments immediately")
    ACTIONS+=("Escalate to engineering lead")
    ACTIONS+=("Emergency review meeting")
    ACTIONS+=("Notify all stakeholders")
elif (( $(echo "$ERROR_BUDGET_CONSUMED >= $CRITICAL_THRESHOLD" | bc -l) )); then
    STATUS="CRITICAL"
    SEVERITY="critical"
    echo -e "${RED}⚠️  CRITICAL: Error budget ${CRITICAL_THRESHOLD}% consumed${NC}"
    ACTIONS+=("Consider freezing deployments for 24h")
    ACTIONS+=("High priority review with SRE team")
    ACTIONS+=("Notify stakeholders")
elif (( $(echo "$ERROR_BUDGET_CONSUMED >= $WARNING_THRESHOLD" | bc -l) )); then
    STATUS="WARNING"
    SEVERITY="warning"
    echo -e "${YELLOW}⚠️  WARNING: Error budget ${WARNING_THRESHOLD}% consumed${NC}"
    ACTIONS+=("Review recent deployments")
    ACTIONS+=("Monitor closely")
    ACTIONS+=("Notify SRE team")
else
    STATUS="OK"
    SEVERITY="info"
    echo -e "${GREEN}✅ Error budget within acceptable limits${NC}"
fi

# Display recommended actions
if [ ${#ACTIONS[@]} -gt 0 ]; then
    echo ""
    echo "📋 Recommended Actions:"
    for action in "${ACTIONS[@]}"; do
        echo "  • $action"
    done
fi

# Export status for automation
export ERROR_BUDGET_STATUS="$STATUS"
export ERROR_BUDGET_CONSUMED="$ERROR_BUDGET_CONSUMED"
export ERROR_BUDGET_REMAINING="$ERROR_BUDGET_REMAINING"
export SEVERITY="$SEVERITY"

# Exit with appropriate code
case "$STATUS" in
    EMERGENCY|CRITICAL)
        exit 2
        ;;
    WARNING)
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
