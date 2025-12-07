#!/bin/bash
# SLO Report Generation Script
# Generates a comprehensive SLO compliance report

set -e

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring.svc.cluster.local:9090}"
SERVICE_NAME="${SERVICE_NAME:-app}"
NAMESPACE="${NAMESPACE:-production}"
SLO_WINDOW="${SLO_WINDOW:-30d}"
ERROR_BUDGET="${ERROR_BUDGET:-0.001}"
OUTPUT_FILE="${OUTPUT_FILE:-slo-report-$(date +%Y%m%d-%H%M%S).json}"

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    local result=$(curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode "query=${query}" | \
        jq -r '.data.result[0].value[1] // "0"')
    echo "$result"
}

echo "Generating SLO Report..."
echo "Service: ${SERVICE_NAME}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Collect all metrics
AVAILABILITY_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"2..|3..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
AVAILABILITY=$(query_prometheus "$AVAILABILITY_QUERY")

ERROR_RATE_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\",status=~\"4..|5..\"}[${SLO_WINDOW}])) / sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}]))"
ERROR_RATE=$(query_prometheus "$ERROR_RATE_QUERY")

P50_QUERY="histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P50=$(query_prometheus "$P50_QUERY")

P95_QUERY="histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P95=$(query_prometheus "$P95_QUERY")

P99_QUERY="histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"${SERVICE_NAME}\"}[${SLO_WINDOW}])) by (le))"
P99=$(query_prometheus "$P99_QUERY")

THROUGHPUT_QUERY="sum(rate(http_requests_total{service=\"${SERVICE_NAME}\"}[5m]))"
THROUGHPUT=$(query_prometheus "$THROUGHPUT_QUERY")

# Calculate error budget
ERROR_BUDGET_CONSUMED=$(echo "scale=4; (1 - $AVAILABILITY) / $ERROR_BUDGET" | bc -l)
ERROR_BUDGET_REMAINING=$(echo "scale=4; 1 - $ERROR_BUDGET_CONSUMED" | bc -l)

# Generate JSON report
jq -n \
  --arg service "$SERVICE_NAME" \
  --arg namespace "$NAMESPACE" \
  --arg window "$SLO_WINDOW" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson availability "$AVAILABILITY" \
  --argjson error_rate "$ERROR_RATE" \
  --argjson p50 "$P50" \
  --argjson p95 "$P95" \
  --argjson p99 "$P99" \
  --argjson throughput "$THROUGHPUT" \
  --argjson error_budget_consumed "$ERROR_BUDGET_CONSUMED" \
  --argjson error_budget_remaining "$ERROR_BUDGET_REMAINING" \
  '{
    service: $service,
    namespace: $namespace,
    window: $window,
    timestamp: $timestamp,
    slis: {
      availability: {
        value: $availability,
        target: 0.999,
        compliant: ($availability >= 0.999)
      },
      error_rate: {
        value: $error_rate,
        target: 0.001,
        compliant: ($error_rate <= 0.001)
      },
      latency_p50: {
        value: $p50,
        target: 0.200,
        compliant: ($p50 <= 0.200)
      },
      latency_p95: {
        value: $p95,
        target: 0.500,
        compliant: ($p95 <= 0.500)
      },
      latency_p99: {
        value: $p99,
        target: 1.000,
        compliant: ($p99 <= 1.000)
      },
      throughput: {
        value: $throughput,
        target: 100,
        compliant: ($throughput >= 100)
      }
    },
    error_budget: {
      total: 0.001,
      consumed: $error_budget_consumed,
      remaining: $error_budget_remaining,
      status: (
        if $error_budget_consumed >= 0.95 then "emergency"
        elif $error_budget_consumed >= 0.80 then "critical"
        elif $error_budget_consumed >= 0.50 then "warning"
        else "ok"
      end
      )
    },
    summary: {
      total_slis: 6,
      compliant_slis: (
        [
          ($availability >= 0.999),
          ($error_rate <= 0.001),
          ($p50 <= 0.200),
          ($p95 <= 0.500),
          ($p99 <= 1.000),
          ($throughput >= 100)
        ] | map(if . then 1 else 0 end) | add
      ),
      overall_compliant: (
        ($availability >= 0.999) and
        ($error_rate <= 0.001) and
        ($p95 <= 0.500) and
        ($p99 <= 1.000)
      )
    }
  }' > "$OUTPUT_FILE"

echo "✅ Report generated: ${OUTPUT_FILE}"
echo ""
echo "Report Summary:"
jq -r '
  "Service: \(.service)
Window: \(.window)
Timestamp: \(.timestamp)

SLI Compliance:
  Availability: \(.slis.availability.value * 100 | tostring | .[0:5])% (Target: 99.9%) - \(if .slis.availability.compliant then "✅" else "❌" end)
  Error Rate: \(.slis.error_rate.value * 100 | tostring | .[0:5])% (Target: 0.1%) - \(if .slis.error_rate.compliant then "✅" else "❌" end)
  P50 Latency: \(.slis.latency_p50.value * 1000 | tostring | .[0:5])ms (Target: 200ms) - \(if .slis.latency_p50.compliant then "✅" else "❌" end)
  P95 Latency: \(.slis.latency_p95.value * 1000 | tostring | .[0:5])ms (Target: 500ms) - \(if .slis.latency_p95.compliant then "✅" else "❌" end)
  P99 Latency: \(.slis.latency_p99.value * 1000 | tostring | .[0:5])ms (Target: 1000ms) - \(if .slis.latency_p99.compliant then "✅" else "❌" end)
  Throughput: \(.slis.throughput.value | tostring | .[0:5]) req/s (Target: 100 req/s) - \(if .slis.throughput.compliant then "✅" else "❌" end)

Error Budget:
  Consumed: \(.error_budget.consumed * 100 | tostring | .[0:5])%
  Remaining: \(.error_budget.remaining * 100 | tostring | .[0:5])%
  Status: \(.error_budget.status | ascii_upcase)

Overall: \(.summary.compliant_slis)/\(.summary.total_slis) SLIs compliant
Overall Status: \(if .summary.overall_compliant then "✅ COMPLIANT" else "❌ NON-COMPLIANT" end)
"' "$OUTPUT_FILE"
