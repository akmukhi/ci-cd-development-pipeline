# Automated Rollback on Error Budget Breach

## Overview

This document describes the automated rollback system that reverts GitOps manifests when error budget thresholds are breached. The system monitors error budget consumption and automatically rolls back deployments to previous working versions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Prometheus Metrics                              │
│  • Error Budget Consumption                                  │
│  • SLO Violations                                           │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│         Error Budget Monitor (CronJob)                       │
│  • Runs every 5 minutes                                      │
│  • Checks error budget consumption                          │
│  • Evaluates rollback triggers                               │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              Rollback Decision Engine                        │
│  • Threshold evaluation                                      │
│  • Safety checks                                             │
│  • Approval requirements                                     │
└─────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        ▼                                     ▼
┌──────────────────┐              ┌──────────────────┐
│  GitOps Rollback  │              │  ArgoCD Rollback  │
│  • Revert commit  │              │  • Rollback app  │
│  • Push to repo  │              │  • Sync changes  │
└──────────────────┘              └──────────────────┘
```

## Rollback Triggers

### 1. Error Budget Thresholds

| Threshold | Consumption | Action |
|-----------|-------------|--------|
| Warning | 50% | Monitor only, no rollback |
| Critical | 80% | Auto-rollback (if enabled) |
| Emergency | 95% | Immediate auto-rollback |

### 2. SLO Violations

- **Availability**: < 99% for 5 minutes
- **Error Rate**: > 1% for 5 minutes
- **Latency**: P95 > 1s or P99 > 2s for 5 minutes

## Configuration

### Environment Variables

```bash
# Prometheus
PROMETHEUS_URL=http://prometheus.monitoring.svc.cluster.local:9090
SERVICE_NAME=app
NAMESPACE=production
SLO_WINDOW=30d
ERROR_BUDGET=0.001

# GitOps
GITOPS_REPO=owner/gitops-repo
GITOPS_TOKEN=ghp_xxxxx
GITOPS_BRANCH=main
GITOPS_PATH=k8s/overlays/prod

# ArgoCD
ARGOCD_SERVER=argocd-server.argocd.svc.cluster.local:443
ARGOCD_APP_NAME=app-prod
ARGOCD_USERNAME=admin
ARGOCD_PASSWORD=xxxxx

# Rollback Policy
ROLLBACK_ENABLED=true
AUTO_ROLLBACK_CRITICAL=true
AUTO_ROLLBACK_EMERGENCY=true
REQUIRE_APPROVAL=false
DRY_RUN=false

# Notifications
SLACK_WEBHOOK=https://hooks.slack.com/services/xxx
PAGERDUTY_KEY=xxxxx
```

## Usage

### Manual Rollback Trigger

```bash
# Run rollback check manually
./scripts/auto-rollback-on-error-budget.sh

# With custom configuration
PROMETHEUS_URL=http://prometheus:9090 \
SERVICE_NAME=app \
ROLLBACK_ENABLED=true \
./scripts/auto-rollback-on-error-budget.sh
```

### GitOps-Only Rollback

```bash
# Rollback GitOps manifest only
./scripts/rollback-gitops-manifest.sh

# With specific commit
TARGET_COMMIT=abc123 \
ROLLBACK_REASON="Manual rollback due to issues" \
./scripts/rollback-gitops-manifest.sh
```

### ArgoCD-Only Rollback

```bash
# Rollback ArgoCD application only
./scripts/rollback-argocd-app.sh

# With specific revision
TARGET_REVISION=abc123 \
./scripts/rollback-argocd-app.sh
```

## Automated Deployment

### Kubernetes CronJob

The rollback monitor runs as a CronJob that executes every 5 minutes:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: error-budget-rollback-monitor
  namespace: monitoring
spec:
  schedule: "*/5 * * * *"
  # ... job template
```

### Deploy Monitor

```bash
# Apply CronJob
kubectl apply -f k8s/monitoring/error-budget-rollback-job.yaml

# Create secrets
kubectl create secret generic gitops-credentials \
  --from-literal=repo=owner/gitops-repo \
  --from-literal=token=ghp_xxxxx \
  -n monitoring

kubectl create secret generic argocd-credentials \
  --from-literal=server=argocd-server.argocd.svc.cluster.local:443 \
  --from-literal=app-name=app-prod \
  --from-literal=password=xxxxx \
  -n monitoring
```

## Safety Mechanisms

### 1. Cooldown Period
- 60 minutes between rollbacks
- Prevents rapid rollback cycles

### 2. Rate Limiting
- Maximum 3 rollbacks per day
- Maximum 1 rollback per hour

### 3. Blackout Periods
- No rollbacks during weekends (00:00-06:00 UTC)
- Configurable blackout windows

### 4. Approval Requirements
- Optional manual approval for production
- Can be enabled via `REQUIRE_APPROVAL=true`

### 5. Dry Run Mode
- Test rollback logic without executing
- Enable via `DRY_RUN=true`

## Rollback Process

### 1. Detection
- Monitor checks error budget every 5 minutes
- Evaluates all rollback triggers
- Checks safety mechanisms

### 2. Decision
- Determines if rollback is needed
- Checks approval requirements
- Validates cooldown periods

### 3. Execution
- **GitOps**: Reverts to previous commit, pushes to repo
- **ArgoCD**: Rolls back to previous revision, syncs application
- Both can run simultaneously

### 4. Validation
- Waits for application sync
- Verifies health status
- Monitors metrics stabilization

### 5. Notification
- Sends alerts to Slack/PagerDuty
- Creates incident tickets
- Notifies on-call team

## Monitoring

### Prometheus Alerts

- `TriggerEmergencyRollback`: Emergency threshold breached
- `TriggerCriticalRollback`: Critical threshold breached
- `RollbackInProgress`: Rollback operation started
- `RollbackCompleted`: Rollback completed successfully
- `RollbackFailed`: Rollback operation failed

### Logs

All rollback operations are logged to:
- `/var/log/error-budget-rollback.log`
- Kubernetes pod logs
- Centralized logging system (if configured)

## Troubleshooting

### Rollback Not Triggering

1. **Check Error Budget**
   ```bash
   ./scripts/check-error-budget.sh
   ```

2. **Verify Configuration**
   ```bash
   kubectl get cronjob error-budget-rollback-monitor -n monitoring
   kubectl get secret gitops-credentials -n monitoring
   ```

3. **Check Logs**
   ```bash
   kubectl logs -l app=error-budget-monitor -n monitoring --tail=100
   ```

### Rollback Failing

1. **Check GitOps Access**
   - Verify token has write permissions
   - Check repository access

2. **Check ArgoCD Connection**
   ```bash
   argocd login $ARGOCD_SERVER
   argocd app get $ARGOCD_APP_NAME
   ```

3. **Verify Previous Revision**
   ```bash
   argocd app history $ARGOCD_APP_NAME
   ```

### False Positives

1. **Adjust Thresholds**
   - Increase error budget thresholds
   - Extend violation duration requirements

2. **Enable Approval**
   - Set `REQUIRE_APPROVAL=true`
   - Review before rollback

3. **Use Dry Run**
   - Test with `DRY_RUN=true`
   - Review logs before enabling

## Best Practices

### 1. Start Conservative
- Begin with approval required
- Use dry run mode initially
- Monitor closely

### 2. Set Appropriate Thresholds
- Base on historical data
- Consider business impact
- Review regularly

### 3. Test Regularly
- Test rollback process
- Verify notifications
- Validate safety mechanisms

### 4. Monitor Closely
- Review rollback logs
- Track success/failure rates
- Adjust based on learnings

### 5. Document Incidents
- Record all rollbacks
- Document root causes
- Update thresholds based on learnings

## Integration with CI/CD

### Pre-Deployment Check

```yaml
- name: Check Error Budget Before Deploy
  run: |
    ./scripts/check-error-budget.sh
    if [ $? -ge 1 ]; then
      echo "Error budget threshold exceeded. Deployment blocked."
      exit 1
    fi
```

### Post-Deployment Monitoring

```yaml
- name: Monitor After Deployment
  run: |
    # Wait for metrics to stabilize
    sleep 300
    # Monitor for 10 minutes
    timeout 600 ./scripts/auto-rollback-on-error-budget.sh || true
```

## References

- [Error Budget Policy](./SLO_ERROR_BUDGET.md)
- [ArgoCD Rollback Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_rollback/)
- [GitOps Best Practices](https://www.gitops.tech/)
