# SLO and Error Budget Guide

## Overview

This document describes the Service Level Objectives (SLOs), Service Level Indicators (SLIs), and Error Budget implementation for the application.

## What are SLIs, SLOs, and Error Budgets?

- **SLI (Service Level Indicator)**: A quantitative measure of some aspect of the level of service provided
- **SLO (Service Level Objective)**: A target value or range of values for a service level that is measured by an SLI
- **Error Budget**: The amount of unreliability that a service can tolerate before users are negatively impacted

## SLI/SLO Definitions

### 1. Availability SLI

**Definition**: Percentage of successful requests (HTTP 2xx, 3xx status codes)

**SLO Target**: 99.9% availability

**Error Budget**: 0.1% (43.2 minutes per month)

**Query**:
```promql
sum(rate(http_requests_total{service="app",status=~"2..|3.."}[30d])) 
/ 
sum(rate(http_requests_total{service="app"}[30d]))
```

### 2. Latency SLIs

#### P50 Latency
- **Target**: 200ms
- **Error Budget**: 1%
- **Query**: `histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service="app"}[30d])) by (le))`

#### P95 Latency
- **Target**: 500ms
- **Error Budget**: 1%
- **Query**: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="app"}[30d])) by (le))`

#### P99 Latency
- **Target**: 1000ms (1s)
- **Error Budget**: 1%
- **Query**: `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="app"}[30d])) by (le))`

### 3. Error Rate SLI

**Definition**: Percentage of requests resulting in errors (HTTP 4xx, 5xx status codes)

**SLO Target**: 0.1% error rate

**Error Budget**: 1%

**Query**:
```promql
sum(rate(http_requests_total{service="app",status=~"4..|5.."}[30d])) 
/ 
sum(rate(http_requests_total{service="app"}[30d]))
```

### 4. Throughput SLI

**Definition**: Requests per second

**SLO Target**: Minimum 100 req/s

**Error Budget**: 5%

**Query**: `sum(rate(http_requests_total{service="app"}[5m]))`

## Error Budget Policy

### Budget Allocation

- **Total Budget**: 0.1% of total time/requests (43.2 minutes per month)
- **Per Incident Max**: 0.01% per incident
- **Daily Burn Rate Limit**: ~0.0033% per day

### Alert Thresholds

| Threshold | Consumption | Action |
|-----------|-------------|--------|
| Warning | 50% | Notify team, review deployments |
| Critical | 80% | Freeze deployments for 24h, high-priority review |
| Emergency | 95% | Freeze deployments for 72h, emergency review, escalate |

### Burn Rate

**Burn Rate** = (Error Rate / Error Budget) × Time Window

- **Normal**: < 6x
- **Elevated**: 6x - 14.4x
- **Critical**: > 14.4x (budget exhausted in <5 hours)

## Usage

### Check SLO Compliance

```bash
# Basic compliance check
./scripts/check-slo-compliance.sh

# With custom parameters
PROMETHEUS_URL=http://prometheus:9090 \
SERVICE_NAME=app \
SLO_WINDOW=30d \
./scripts/check-slo-compliance.sh
```

### Monitor Error Budget

```bash
# Check error budget consumption
./scripts/check-error-budget.sh

# The script will:
# - Calculate current error budget consumption
# - Display burn rates
# - Estimate time until exhaustion
# - Recommend actions based on thresholds
```

### Generate SLO Report

```bash
# Generate comprehensive SLO report
./scripts/generate-slo-report.sh

# Output will be saved to: slo-report-YYYYMMDD-HHMMSS.json

# View report summary
cat slo-report-*.json | jq '.summary'
```

## Prometheus Alerts

### Availability SLO Breach
- **Alert**: `AvailabilitySLOBreach`
- **Condition**: Availability < 99.9%
- **Severity**: Critical
- **Duration**: 5 minutes

### Error Budget Alerts

1. **ErrorBudgetWarning** (50% consumed)
   - Severity: Warning
   - Action: Review deployments

2. **ErrorBudgetCritical** (80% consumed)
   - Severity: Critical
   - Action: Consider freezing deployments

3. **ErrorBudgetEmergency** (95% consumed)
   - Severity: Critical
   - Action: Freeze all deployments immediately

### Latency SLO Alerts

- **LatencyP95SLOBreach**: P95 latency > 500ms
- **LatencyP99SLOBreach**: P99 latency > 1000ms

### Burn Rate Alert

- **HighErrorBudgetBurnRate**: Burn rate > 14.4x
- Indicates budget will be exhausted in <5 hours

## Integration with CI/CD

### Pre-Deployment Checks

Add to your CI/CD pipeline:

```yaml
- name: Check Error Budget Before Deployment
  run: |
    ./scripts/check-error-budget.sh
    if [ $? -ge 1 ]; then
      echo "Error budget threshold exceeded. Deployment blocked."
      exit 1
    fi
```

### Post-Deployment Validation

```yaml
- name: Validate SLO Compliance
  run: |
    sleep 300  # Wait 5 minutes for metrics to stabilize
    ./scripts/check-slo-compliance.sh
```

## Best Practices

### 1. Set Realistic SLOs
- Base SLOs on user expectations
- Consider business requirements
- Review and adjust regularly

### 2. Monitor Continuously
- Set up automated checks
- Review reports regularly
- Track trends over time

### 3. Use Error Budgets Wisely
- Don't be afraid to use the budget for improvements
- Balance reliability with feature velocity
- Learn from incidents

### 4. Respond to Thresholds
- Take action at warning thresholds
- Don't wait for critical alerts
- Document decisions and learnings

### 5. Review and Adjust
- Monthly SLO reviews
- Quarterly error budget policy review
- Adjust based on learnings

## Troubleshooting

### High Error Budget Consumption

1. **Identify Root Cause**
   - Review recent deployments
   - Check incident reports
   - Analyze error patterns

2. **Immediate Actions**
   - Freeze deployments if at critical threshold
   - Rollback problematic changes
   - Increase monitoring

3. **Long-term Actions**
   - Improve testing
   - Enhance monitoring
   - Review deployment process

### SLO Violations

1. **Check Metrics**
   - Verify Prometheus queries
   - Check metric collection
   - Review time windows

2. **Investigate Issues**
   - Review application logs
   - Check infrastructure health
   - Analyze traffic patterns

3. **Take Corrective Action**
   - Fix underlying issues
   - Optimize performance
   - Scale resources if needed

## References

- [Google SRE Book - SLIs, SLOs, and SLAs](https://sre.google/sre-book/service-level-objectives/)
- [Prometheus Querying](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Error Budget Policy Template](https://sre.google/workbook/error-budget-policy/)
