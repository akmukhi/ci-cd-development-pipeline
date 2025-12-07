# Monitoring and Alerting Guide

## Overview

This document describes the Prometheus metrics queries, Grafana dashboards, and alerting rules for comprehensive monitoring and observability.

## Prometheus Queries

### Application Metrics

#### Request Rate
```promql
# Total request rate
sum(rate(http_requests_total{service="app"}[5m])) by (service, namespace, environment)

# Request rate by method
sum(rate(http_requests_total{service="app"}[5m])) by (method, service)

# Request rate by status
sum(rate(http_requests_total{service="app"}[5m])) by (status, service)
```

#### Error Rate
```promql
# Overall error rate
sum(rate(http_requests_total{service="app",status=~"4..|5.."}[5m])) 
/ 
sum(rate(http_requests_total{service="app"}[5m]))

# 4xx error rate
sum(rate(http_requests_total{service="app",status=~"4.."}[5m])) 
/ 
sum(rate(http_requests_total{service="app"}[5m]))

# 5xx error rate
sum(rate(http_requests_total{service="app",status=~"5.."}[5m])) 
/ 
sum(rate(http_requests_total{service="app"}[5m]))
```

#### Latency
```promql
# P50 latency
histogram_quantile(0.50, 
  sum(rate(http_request_duration_seconds_bucket{service="app"}[5m])) by (le, service)
)

# P95 latency
histogram_quantile(0.95, 
  sum(rate(http_request_duration_seconds_bucket{service="app"}[5m])) by (le, service)
)

# P99 latency
histogram_quantile(0.99, 
  sum(rate(http_request_duration_seconds_bucket{service="app"}[5m])) by (le, service)
)
```

### SLO Metrics

#### Availability
```promql
# 30-day availability
sum(rate(http_requests_total{service="app",status=~"2..|3.."}[30d])) 
/ 
sum(rate(http_requests_total{service="app"}[30d]))

# 7-day availability
sum(rate(http_requests_total{service="app",status=~"2..|3.."}[7d])) 
/ 
sum(rate(http_requests_total{service="app"}[7d]))

# 24-hour availability
sum(rate(http_requests_total{service="app",status=~"2..|3.."}[24h])) 
/ 
sum(rate(http_requests_total{service="app"}[24h]))
```

#### Error Budget
```promql
# Error budget consumption
(1 - (
  sum(rate(http_requests_total{service="app",status=~"2..|3.."}[30d])) 
  / 
  sum(rate(http_requests_total{service="app"}[30d]))
)) / 0.001

# Error budget remaining
1 - ((1 - (
  sum(rate(http_requests_total{service="app",status=~"2..|3.."}[30d])) 
  / 
  sum(rate(http_requests_total{service="app"}[30d]))
)) / 0.001)

# Burn rate (6h)
(1 - (
  sum(rate(http_requests_total{service="app",status=~"2..|3.."}[6h])) 
  / 
  sum(rate(http_requests_total{service="app"}[6h]))
)) / 0.001
```

### Resource Metrics

#### CPU
```promql
# CPU usage percentage
sum(rate(container_cpu_usage_seconds_total{pod=~"app-.*"}[5m])) by (pod, namespace) * 100

# CPU requests utilization
sum(rate(container_cpu_usage_seconds_total{pod=~"app-.*"}[5m])) 
/ 
sum(kube_pod_container_resource_requests{pod=~"app-.*",resource="cpu"}) * 100
```

#### Memory
```promql
# Memory usage bytes
sum(container_memory_usage_bytes{pod=~"app-.*"}) by (pod, namespace)

# Memory usage percentage
sum(container_memory_usage_bytes{pod=~"app-.*"}) 
/ 
sum(container_spec_memory_limit_bytes{pod=~"app-.*"}) * 100
```

### Canary Metrics

```promql
# Canary traffic percentage
sum(rate(http_requests_total{service="app",track="canary"}[5m])) 
/ 
sum(rate(http_requests_total{service="app"}[5m])) * 100

# Canary vs Stable success rate
sum(rate(http_requests_total{service="app",track="canary",status=~"2..|3.."}[5m])) 
/ 
sum(rate(http_requests_total{service="app",track="canary"}[5m]))
```

## Grafana Dashboards

### Application Monitoring Dashboard

**Location**: `monitoring/grafana-dashboard-app.json`

**Panels**:
1. Request Rate - Total requests per second
2. Error Rate - Percentage of errors
3. Success Rate - Percentage of successful requests
4. P95 Latency - 95th percentile latency
5. Latency Percentiles - P50, P95, P99 comparison
6. CPU Usage - CPU usage per pod
7. Memory Usage - Memory usage per pod
8. Availability (30-day) - Long-term availability
9. Error Budget Remaining - Remaining error budget
10. Pod Status - Number of pods

### SLO & Error Budget Dashboard

**Location**: `monitoring/grafana-dashboard-slo.json`

**Panels**:
1. Availability (30-day Rolling) - Long-term availability trend
2. Error Budget Consumption - Error budget usage over time
3. Error Budget Remaining - Gauge showing remaining budget
4. Burn Rate (6h) - 6-hour burn rate
5. Burn Rate (1h) - 1-hour burn rate
6. Availability by Time Window - 24h, 7d, 30d comparison
7. Error Rate Trend - Error rate over time
8. Latency SLO Compliance - P95 latency vs SLO target

### Importing Dashboards

```bash
# Import via Grafana API
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -d @monitoring/grafana-dashboard-app.json \
  http://grafana:3000/api/dashboards/db

# Or import via Grafana UI
# 1. Go to Dashboards > Import
# 2. Upload JSON file or paste contents
# 3. Configure data source
# 4. Save dashboard
```

## Alerting Rules

### Application Health Alerts

- **HighErrorRate**: Error rate > 5% for 5 minutes
- **CriticalErrorRate**: Error rate > 10% for 2 minutes
- **LowSuccessRate**: Success rate < 95% for 5 minutes
- **VeryLowSuccessRate**: Success rate < 90% for 2 minutes
- **HighLatency**: P95 latency > 1s for 5 minutes
- **VeryHighLatency**: P95 latency > 2s for 2 minutes
- **LowThroughput**: Throughput < 10 req/s for 10 minutes

### Resource Alerts

- **HighCPUUsage**: CPU usage > 80% for 5 minutes
- **CriticalCPUUsage**: CPU usage > 95% for 2 minutes
- **HighMemoryUsage**: Memory usage > 80% for 5 minutes
- **CriticalMemoryUsage**: Memory usage > 95% for 2 minutes
- **PodRestarting**: Pod restarted > 3 times in 1 hour
- **PodCrashLooping**: Pod in CrashLoopBackOff state

### Deployment Alerts

- **DeploymentNotReady**: Deployment has unavailable replicas
- **DeploymentManyUnavailable**: > 50% replicas unavailable
- **HPAAtMaxReplicas**: HPA at maximum replicas for 10 minutes
- **HPAAtMinReplicas**: HPA at minimum replicas for 30 minutes

### Canary Alerts

- **CanaryHighErrorRate**: Canary error rate > 10% for 2 minutes
- **CanaryLowSuccessRate**: Canary success rate < 90% for 2 minutes
- **CanaryLatencySpike**: Canary P95 latency > 1.5s for 3 minutes

### SLO Alerts

- **AvailabilitySLOBreach**: 30-day availability < 99.9%
- **ErrorBudgetWarning**: Error budget 50% consumed
- **ErrorBudgetCritical**: Error budget 80% consumed
- **ErrorBudgetEmergency**: Error budget 95% consumed

## Alert Severity Levels

- **Critical**: Immediate action required, service impact
- **Warning**: Attention needed, potential service impact
- **Info**: Informational, no immediate action required

## Alert Routing

### Critical Alerts
- PagerDuty (on-call)
- Slack (#critical-alerts)
- Email (SRE team)

### Warning Alerts
- Slack (#alerts)
- Email (team)

### Info Alerts
- Slack (#monitoring)

## Best Practices

### 1. Use Appropriate Time Windows
- Short windows (1-5m) for immediate issues
- Longer windows (30d) for SLO calculations
- Balance between detection speed and false positives

### 2. Set Realistic Thresholds
- Base on historical data
- Consider business impact
- Review and adjust regularly

### 3. Avoid Alert Fatigue
- Use appropriate severity levels
- Group related alerts
- Use alert inhibition rules

### 4. Monitor Trends
- Use Grafana dashboards for trends
- Set up weekly/monthly reviews
- Track SLO compliance over time

### 5. Document Runbooks
- Link runbooks in alert annotations
- Keep runbooks up to date
- Include troubleshooting steps

## Troubleshooting

### Missing Metrics

1. **Check ServiceMonitor**
   ```bash
   kubectl get servicemonitor -n monitoring
   kubectl describe servicemonitor app -n monitoring
   ```

2. **Check Prometheus Targets**
   - Go to Prometheus UI
   - Check Status > Targets
   - Verify endpoints are up

3. **Check Metrics Endpoint**
   ```bash
   curl http://app-service:8080/metrics
   ```

### Alerts Not Firing

1. **Check Alert Rules**
   ```bash
   kubectl get prometheusrule -n monitoring
   kubectl describe prometheusrule comprehensive-alerts -n monitoring
   ```

2. **Check Alertmanager**
   - Verify Alertmanager is running
   - Check alert routing configuration
   - Review silence/inhibition rules

3. **Test Alert Expression**
   - Run query in Prometheus UI
   - Verify results match expectations

## References

- [Prometheus Query Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboard Documentation](https://grafana.com/docs/grafana/latest/dashboards/)
- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [PrometheusRule CRD](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PrometheusRule)
