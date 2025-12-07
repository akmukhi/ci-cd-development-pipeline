# Canary Deployment Strategy

This directory contains the Kubernetes manifests for canary deployments with progressive traffic rollout and automated monitoring.

## Overview

The canary deployment strategy uses **Argo Rollouts** to gradually shift traffic from the stable version to the canary version, with automated analysis and rollback capabilities.

## Traffic Rollout Steps

The canary deployment follows these progressive steps:

1. **10% Traffic** - Initial canary deployment (2 minutes observation)
2. **25% Traffic** - First increase (5 minutes observation)
3. **50% Traffic** - Half traffic (5 minutes observation)
4. **75% Traffic** - Majority traffic (5 minutes observation)
5. **100% Traffic** - Full rollout (10 minutes final observation)

## Monitoring & Analysis

### Metrics Collected

- **Success Rate**: Percentage of successful HTTP requests (2xx status codes)
- **Error Rate**: Percentage of failed HTTP requests (5xx status codes)
- **Latency (P95)**: 95th percentile response time
- **Request Volume**: Total number of requests per second

### Analysis Conditions

**Success Conditions** (must all be met):
- Success rate ≥ 95%
- Error rate ≤ 5%
- P95 latency ≤ 500ms

**Failure Conditions** (triggers rollback):
- Success rate < 90%
- Error rate > 10%
- P95 latency > 1000ms

### Automated Actions

- **3 consecutive failures** → Automatic rollback
- **All success conditions met** → Automatic promotion to next step
- **Analysis runs every 30 seconds** during each step

## Usage

### Deploy Canary

```bash
# Apply the canary overlay
kubectl apply -k k8s/overlays/canary

# Or via ArgoCD
argocd app sync app-canary
```

### Monitor Canary

```bash
# Watch rollout status
kubectl argo rollouts get rollout canary-app -n production --watch

# View rollout history
kubectl argo rollouts history canary-app -n production

# Check analysis results
kubectl argo rollouts get rollout canary-app -n production
```

### Manual Promotion

```bash
# Promote to next step
kubectl argo rollouts promote canary-app -n production

# Or use the promotion script
./scripts/canary-promote.sh
```

### Manual Rollback

```bash
# Rollback to previous revision
kubectl argo rollouts undo canary-app -n production

# Or use the rollback script
./scripts/canary-rollback.sh
```

## Grafana Dashboard

Access the canary monitoring dashboard in Grafana:
- Dashboard: "Canary Deployment Monitoring"
- Metrics include:
  - Request rate comparison (Canary vs Stable)
  - Error rate comparison
  - Latency comparison (P95)
  - Traffic split percentage
  - Success rate comparison

## Alerts

Prometheus alerts are configured for:
- High error rate (>10%)
- Low success rate (<90%)
- Latency spikes (P95 >1.5s)
- Traffic imbalance

## Prerequisites

1. **Argo Rollouts** controller installed in the cluster
2. **Istio** service mesh for traffic splitting
3. **Prometheus** for metrics collection
4. **Grafana** for visualization (optional)

## Configuration

Key configuration files:
- `rollout-patch.yaml` - Rollout strategy and steps
- `analysis-template-patch.yaml` - Analysis metrics
- `virtualservice-patch.yaml` - Traffic routing rules
- `servicemonitor-patch.yaml` - Prometheus scraping config
- `prometheusrule-patch.yaml` - Alerting rules

## Best Practices

1. **Start Small**: Begin with 10% traffic to minimize impact
2. **Monitor Closely**: Watch metrics during each step
3. **Set Appropriate Thresholds**: Adjust success/failure conditions based on your SLA
4. **Use Automated Analysis**: Let Argo Rollouts handle promotion/rollback
5. **Test in Staging First**: Validate canary strategy in staging before production
