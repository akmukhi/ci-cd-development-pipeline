# Canary Deployment Strategy Guide

## Overview

This document describes the canary deployment strategy implemented using Argo Rollouts with progressive traffic rollout and automated monitoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Traffic Flow                              │
│                                                              │
│  Users → Istio VirtualService → [90% Stable] [10% Canary]  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Argo Rollouts Controller                        │
│  • Manages canary deployment                                │
│  • Controls traffic weights                                 │
│  • Runs automated analysis                                  │
│  • Handles promotion/rollback                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Prometheus Monitoring                           │
│  • Collects metrics from canary & stable                    │
│  • Provides data for analysis                               │
│  • Triggers alerts on anomalies                            │
└─────────────────────────────────────────────────────────────┘
```

## Progressive Traffic Rollout

The canary deployment follows a 5-step progressive rollout:

| Step | Traffic % | Duration | Purpose |
|------|-----------|----------|---------|
| 1    | 10%       | 2 min    | Initial validation |
| 2    | 25%       | 5 min    | Extended testing |
| 3    | 50%       | 5 min    | Half traffic validation |
| 4    | 75%       | 5 min    | Majority traffic test |
| 5    | 100%      | 10 min   | Full rollout validation |

### Traffic Splitting

Traffic is split using Istio VirtualService:
- **Stable**: Receives (100 - canary%) of traffic
- **Canary**: Receives canary% of traffic
- Traffic can be split by:
  - Weight-based routing (default)
  - Header-based routing (x-canary: "true")
  - Cookie-based routing

## Monitoring & Metrics

### Key Metrics

1. **Success Rate**
   - Target: ≥ 95%
   - Failure threshold: < 90%
   - Formula: `(2xx requests / total requests) * 100`

2. **Error Rate**
   - Target: ≤ 5%
   - Failure threshold: > 10%
   - Formula: `(5xx requests / total requests) * 100`

3. **Latency (P95)**
   - Target: ≤ 500ms
   - Failure threshold: > 1000ms
   - Formula: `95th percentile of response times`

4. **Request Volume**
   - Minimum: ≥ 10 req/s
   - Ensures sufficient traffic for meaningful analysis

5. **Resource Usage**
   - CPU: Target ≤ 80%, Alert > 90%
   - Memory: Target ≤ 80%, Alert > 90%

### Analysis Configuration

```yaml
analysis:
  startingStep: 1      # Start from step 1
  interval: 30s       # Check every 30 seconds
  successCondition: |
    success-rate >= 0.95 and 
    error-rate <= 0.05 and 
    latency-p95 <= 500
  failureCondition: |
    success-rate < 0.90 or 
    error-rate > 0.10 or 
    latency-p95 > 1000
  failureLimit: 3      # 3 failures = rollback
  count: 10            # 10 checks per step
```

## Automated Actions

### Automatic Promotion

The canary automatically promotes to the next step when:
- All success conditions are met
- Analysis runs successfully for the step duration
- No failures detected

### Automatic Rollback

The canary automatically rolls back when:
- Failure conditions are met 3 times consecutively
- Critical metrics exceed thresholds
- Health checks fail repeatedly

## Manual Operations

### Promote Canary

```bash
# Promote to next step
kubectl argo rollouts promote canary-app -n production

# Or use script
./scripts/canary-promote.sh
```

### Rollback Canary

```bash
# Rollback to previous revision
kubectl argo rollouts undo canary-app -n production

# Or use script
./scripts/canary-rollback.sh
```

### View Status

```bash
# Watch rollout status
kubectl argo rollouts get rollout canary-app -n production --watch

# View history
kubectl argo rollouts history canary-app -n production

# View analysis results
kubectl argo rollouts get rollout canary-app -n production
```

## Grafana Dashboards

### Canary Deployment Monitoring Dashboard

Access: `http://grafana.example.com/d/canary-deployment`

**Panels:**
1. **Request Rate Comparison** - Canary vs Stable
2. **Error Rate Comparison** - Side-by-side error rates
3. **P95 Latency Comparison** - Response time comparison
4. **Traffic Split Gauge** - Current canary traffic percentage
5. **Success Rate Comparison** - Success rate trends

## Prometheus Alerts

### Alert Rules

1. **CanaryHighErrorRate**
   - Condition: Error rate > 10%
   - Severity: Critical
   - Duration: 2 minutes

2. **CanaryLowSuccessRate**
   - Condition: Success rate < 90%
   - Severity: Critical
   - Duration: 2 minutes

3. **CanaryLatencySpike**
   - Condition: P95 latency > 1.5s
   - Severity: Warning
   - Duration: 3 minutes

4. **CanaryTrafficImbalance**
   - Condition: Traffic > expected percentage
   - Severity: Info
   - Duration: 5 minutes

## Best Practices

### 1. Start Small
- Begin with 10% traffic to minimize impact
- Gradually increase based on metrics

### 2. Monitor Closely
- Watch Grafana dashboards during rollout
- Set up alert notifications
- Review analysis results

### 3. Set Appropriate Thresholds
- Adjust success/failure conditions based on SLA
- Consider business requirements
- Account for traffic patterns

### 4. Use Automated Analysis
- Let Argo Rollouts handle promotion/rollback
- Trust the metrics and analysis
- Intervene only when necessary

### 5. Test in Staging First
- Validate canary strategy in staging
- Test rollback procedures
- Verify monitoring setup

### 6. Document Incidents
- Record any rollbacks and reasons
- Update thresholds based on learnings
- Share knowledge with team

## Troubleshooting

### Canary Not Receiving Traffic

1. Check VirtualService configuration
2. Verify Istio is properly configured
3. Check destination rules
4. Review rollout status

### Analysis Failing

1. Verify Prometheus is accessible
2. Check metric names match
3. Review query syntax
4. Ensure metrics are being collected

### Rollback Not Working

1. Check rollout history
2. Verify stable revision exists
3. Review rollout controller logs
4. Check resource limits

## Prerequisites

- **Argo Rollouts** v1.5+ installed
- **Istio** service mesh configured
- **Prometheus** for metrics collection
- **Grafana** for visualization (optional)
- **kubectl-argo-rollouts** plugin installed

## Configuration Files

- `rollout-enhanced.yaml` - Rollout strategy
- `analysis-template-enhanced.yaml` - Analysis metrics
- `virtualservice-patch.yaml` - Traffic routing
- `servicemonitor-patch.yaml` - Prometheus scraping
- `prometheusrule-patch.yaml` - Alert rules
- `grafana-dashboard.yaml` - Dashboard config

## References

- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Istio Traffic Management](https://istio.io/latest/docs/tasks/traffic-management/)
- [Prometheus Querying](https://prometheus.io/docs/prometheus/latest/querying/basics/)
