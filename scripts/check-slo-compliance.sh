#!/bin/bash
# SLO Compliance Checking Script
# Checks current SLI values against SLO targets and error budget consumption

set -e

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
SERVICE_NAME="${SERVICE_NAME:-app}"
NAMESPACE="${NAMESPACE:-production}"
SLO_WINDOW="${SLO_WINDOW:-30d}"
ERROR_BUDGET="${ERROR_BUDGET:-0.001}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to format duration
format_duration() {
    local seconds="$1"
    if (( $(echo "$seconds < 60" | bc -l) )); then
        printf "%.2fs" "$seconds"
    elif (( $(echo "$seconds < 3600" | bc -l) )); then
        printf "%.2fm" $(echo "$seconds / 60" | bc -l)
    else
        printf "%.2fh" $(echo "$seconds / 3600" | bc -l)
    fi
}

echo "=========================================="
echo "SLO Compliance Check"
echo "=========================================="
echo "Service: ${SERVICE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "SLO Window: ${SLO_WINDOW}"
echo "Prometheus: ${PROMETHEUS_URL}"
echo ""

# Check if Prometheus is accessible
if ! curl -s "${PROMETHEUS_URL}/api/v1/status/config" > /dev/null; then
    echo -e "${RED}❌ Error: Cannot connect to Prometheus at ${PROMETHEUS_URL}${NC}"
    exit 1
fi

# 1. Availability SLI
echo "📊 Checking Availability SLI..."
AVAILABILITY_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
AVAILABILITY=$(query_prometheus "$AVAILABILITY_QUERY")
AVAILABILITY_TARGET=0.999
AVAILABILITY_PCT=$(format_percentage "$AVAILABILITY")

if (( $(echo "$AVAILABILITY >= $AVAILABILITY_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ Availability: ${AVAILABILITY_PCT} (Target: 99.9%)${NC}"
else
    echo -e "  ${RED}❌ Availability: ${AVAILABILITY_PCT} (Target: 99.9%)${NC}"
fi

# 2. Error Budget Consumption
echo ""
echo "💰 Checking Error Budget Consumption..."
ERROR_BUDGET_CONSUMED=$(echo "scale=4; (1 - $AVAILABILITY) / $ERROR_BUDGET" | bc -l)
ERROR_BUDGET_CONSUMED_PCT=$(format_percentage "$ERROR_BUDGET_CONSUMED")
ERROR_BUDGET_REMAINING=$(echo "scale=4; 1 - $ERROR_BUDGET_CONSUMED" | bc -l)
ERROR_BUDGET_REMAINING_PCT=$(format_percentage "$ERROR_BUDGET_REMAINING")

if (( $(echo "$ERROR_BUDGET_CONSUMED < 0.50" | bc -l) )); then
    echo -e "  ${GREEN}✅ Error Budget: ${ERROR_BUDGET_CONSUMED_PCT} consumed, ${ERROR_BUDGET_REMAINING_PCT} remaining${NC}"
elif (( $(echo "$ERROR_BUDGET_CONSUMED < 0.80" | bc -l) )); then
    echo -e "  ${YELLOW}⚠️  Error Budget: ${ERROR_BUDGET_CONSUMED_PCT} consumed, ${ERROR_BUDGET_REMAINING_PCT} remaining${NC}"
else
    echo -e "  ${RED}🚨 Error Budget: ${ERROR_BUDGET_CONSUMED_PCT} consumed, ${ERROR_BUDGET_REMAINING_PCT} remaining${NC}"
fi

# 3. Latency SLIs
echo ""
echo "⏱️  Checking Latency SLIs..."

# P50 Latency
P50_QUERY="histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P50=$(query_prometheus "$P50_QUERY")
P50_TARGET=0.200
P50_MS=$(echo "$P50 * 1000" | bc -l)

if (( $(echo "$P50 <= $P50_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ P50 Latency: ${P50_MS}ms (Target: 200ms)${NC}"
else
    echo -e "  ${RED}❌ P50 Latency: ${P50_MS}ms (Target: 200ms)${NC}"
fi

# P95 Latency
P95_QUERY="histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P95=$(query_prometheus "$P95_QUERY")
P95_TARGET=0.500
P95_MS=$(echo "$P95 * 1000" | bc -l)

if (( $(echo "$P95 <= $P95_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ P95 Latency: ${P95_MS}ms (Target: 500ms)${NC}"
else
    echo -e "  ${RED}❌ P95 Latency: ${P95_MS}ms (Target: 500ms)${NC}"
fi

# P99 Latency
P99_QUERY="histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P99=$(query_prometheus "$P99_QUERY")
P99_TARGET=1.000
P99_MS=$(echo "$P99 * 1000" | bc -l)

if (( $(echo "$P99 <= $P99_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ P99 Latency: ${P99_MS}ms (Target: 1000ms)${NC}"
else
    echo -e "  ${RED}❌ P99 Latency: ${P99_MS}ms (Target: 1000ms)${NC}"
fi

# 4. Error Rate SLI
echo ""
echo "🚨 Checking Error Rate SLI..."
ERROR_RATE_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"4..|5..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
ERROR_RATE=$(query_prometheus "$ERROR_RATE_QUERY")
ERROR_RATE_TARGET=0.001
ERROR_RATE_PCT=$(format_percentage "$ERROR_RATE")

if (( $(echo "$ERROR_RATE <= $ERROR_RATE_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ Error Rate: ${ERROR_RATE_PCT} (Target: 0.1%)${NC}"
else
    echo -e "  ${RED}❌ Error Rate: ${ERROR_RATE_PCT} (Target: 0.1%)${NC}"
fi

# 5. Throughput SLI
echo ""
echo "📈 Checking Throughput SLI..."
THROUGHPUT_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[5m]))"
THROUGHPUT=$(query_prometheus "$THROUGHPUT_QUERY")
THROUGHPUT_TARGET=100

if (( $(echo "$THROUGHPUT >= $THROUGHPUT_TARGET" | bc -l) )); then
    echo -e "  ${GREEN}✅ Throughput: ${THROUGHPUT} req/s (Target: 100 req/s)${NC}"
else
    echo -e "  ${YELLOW}⚠️  Throughput: ${THROUGHPUT} req/s (Target: 100 req/s)${NC}"
fi

# 6. Burn Rate Calculation
echo ""
echo "🔥 Calculating Error Budget Burn Rate..."
BURN_RATE_6H=$(echo "scale=4; (1 - (sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[6h])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[6h])))) / $ERROR_BUDGET" | bc -l)
BURN_RATE_1H=$(echo "scale=4; (1 - (sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[1h])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[1h])))) / $ERROR_BUDGET" | bc -l)

if (( $(echo "$BURN_RATE_6H < 6.0" | bc -l) )); then
    echo -e "  ${GREEN}✅ 6h Burn Rate: ${BURN_RATE_6H}x (Normal)${NC}"
elif (( $(echo "$BURN_RATE_6H < 14.4" | bc -l) )); then
    echo -e "  ${YELLOW}⚠️  6h Burn Rate: ${BURN_RATE_6H}x (Elevated)${NC}"
else
    echo -e "  ${RED}🚨 6h Burn Rate: ${BURN_RATE_6H}x (Critical - budget exhausted in <5h)${NC}"
fi

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

# Count violations
VIOLATIONS=0
(( $(echo "$AVAILABILITY < $AVAILABILITY_TARGET" | bc -l) )) && ((VIOLATIONS++))
(( $(echo "$P95 > $P95_TARGET" | bc -l) )) && ((VIOLATIONS++))
(( $(echo "$ERROR_RATE > $ERROR_RATE_TARGET" | bc -l) )) && ((VIOLATIONS++))

if [ $VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}✅ All SLOs are being met${NC}"
    exit 0
else
    echo -e "${RED}❌ ${VIOLATIONS} SLO violation(s) detected${NC}"
    exit 1
fi
