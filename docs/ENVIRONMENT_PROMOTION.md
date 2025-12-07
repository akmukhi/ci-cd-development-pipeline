# Environment Promotion Guide

## Overview

This document describes the automated environment promotion system that promotes applications between environments (dev → staging → canary → production) based on configured rules and requirements.

## Promotion Flow

```
┌─────────┐      ┌──────────┐      ┌─────────┐      ┌──────────┐
│   Dev   │ ───> │ Staging  │ ───> │ Canary  │ ───> │ Production│
└─────────┘      └──────────┘      └─────────┘      └──────────┘
     │                │                 │                 │
     │                │                 │                 │
     ▼                ▼                 ▼                 ▼
  Tests          Tests +          Tests +          Tests +
  Security       Security         Security         Security
  Quality        Quality          Quality          Quality
                 SLO              SLO              SLO
                                 Error Budget     Error Budget
                                 Canary Metrics   Approval
```

## Promotion Rules

### Dev → Staging

**Requirements:**
- ✅ Unit tests passed
- ✅ Integration tests passed
- ✅ Code coverage ≥ 70%
- ✅ Security scan passed (max 5 high, 0 critical)
- ✅ SLO: Availability ≥ 99%, Error rate ≤ 1%
- ✅ Error budget consumption < 50%
- ✅ No critical alerts
- ⚠️ Approval: Not required

**Auto-promote:** Disabled

### Staging → Canary

**Requirements:**
- ✅ All tests passed (including E2E)
- ✅ Code coverage ≥ 80%
- ✅ Security scan passed (max 0 high, 0 critical)
- ✅ SLO: Availability ≥ 99.5%, Error rate ≤ 0.5%
- ✅ Error budget consumption < 30%
- ✅ Performance tests passed
- ⚠️ Approval: Required (SRE + QA)

**Auto-promote:** Disabled

### Canary → Production

**Requirements:**
- ✅ All tests passed (including E2E, performance)
- ✅ Code coverage ≥ 85%
- ✅ Security scan passed (max 0 high, 0 critical)
- ✅ SLO: Availability ≥ 99.9%, Error rate ≤ 0.1%
- ✅ Error budget consumption < 20%
- ✅ Canary metrics: 10% traffic, 24h duration, 99% success rate
- ⚠️ Approval: Required (SRE + Engineering Lead + Product Owner)

**Auto-promote:** Disabled

## Usage

### Manual Promotion

```bash
# Promote from dev to staging
FROM_ENV=dev TO_ENV=staging ./scripts/promote-environment.sh

# Promote from staging to canary (requires approval)
FROM_ENV=staging TO_ENV=canary ./scripts/promote-environment.sh

# Promote with auto-approve
FROM_ENV=canary TO_ENV=production AUTO_APPROVE=true ./scripts/promote-environment.sh
```

### Validate Requirements Only

```bash
# Check if promotion requirements are met
FROM_ENV=staging TO_ENV=canary ./scripts/validate-promotion-requirements.sh
```

### GitHub Actions Workflow

```bash
# Trigger promotion via GitHub Actions
gh workflow run promotion-workflow.yml \
  -f from_env=staging \
  -f to_env=canary \
  -f auto_approve=false
```

## Promotion Process

### 1. Pre-Promotion Validation

The system validates:
- ✅ Test results
- ✅ Security scans
- ✅ Code quality
- ✅ SLO compliance
- ✅ Error budget
- ✅ Deployment stability
- ✅ Critical alerts

### 2. Approval Check

- **Dev → Staging**: No approval required
- **Staging → Canary**: Requires SRE + QA approval
- **Canary → Production**: Requires SRE + Engineering Lead + Product Owner approval

### 3. Promotion Execution

1. **GitOps Update**: Updates target environment manifest with source environment image
2. **ArgoCD Sync**: Syncs target ArgoCD application
3. **Deployment**: ArgoCD deploys the new version

### 4. Post-Promotion Validation

- ✅ Deployment successful
- ✅ Health checks passing
- ✅ Metrics stable
- ✅ Smoke tests passing

## Configuration

### Environment Variables

```bash
# Source and target environments
FROM_ENV=dev
TO_ENV=staging

# GitOps configuration
GITOPS_REPO=owner/gitops-repo
GITOPS_TOKEN=ghp_xxxxx
GITOPS_BRANCH=main

# ArgoCD configuration
ARGOCD_SERVER=argocd-server.argocd.svc.cluster.local:443
ARGOCD_USERNAME=admin
ARGOCD_PASSWORD=xxxxx

# Options
AUTO_APPROVE=false
DRY_RUN=false
SKIP_VALIDATION=false
```

### Promotion Rules File

Edit `promotion/promotion-rules.yaml` to customize:
- Promotion requirements
- Approval workflows
- SLO thresholds
- Error budget limits

## Safety Mechanisms

### 1. Validation Gates

All promotion gates must pass before promotion:
- Tests passed
- Security scans passed
- Code quality passed
- SLO compliant
- Error budget OK
- Deployment stable
- No critical alerts

### 2. Approval Requirements

- Manual approval for production promotions
- Multiple approver requirements
- Approval tracking and audit

### 3. Rollback on Failure

- Automatic rollback if post-promotion validation fails
- Rollback triggers:
  - Error budget breach
  - SLO violation
  - Critical alert
  - Deployment failure
  - Health check failure

### 4. Dry Run Mode

Test promotion without executing:
```bash
DRY_RUN=true ./scripts/promote-environment.sh
```

## Monitoring

### Promotion Metrics

Track promotion success/failure rates:
- Promotion attempts
- Successful promotions
- Failed promotions
- Average promotion time
- Validation failures by type

### Alerts

- Promotion failure alerts
- Validation failure alerts
- Approval required notifications

## Troubleshooting

### Promotion Failing Validation

1. **Check Validation Report**
   ```bash
   ./scripts/validate-promotion-requirements.sh
   ```

2. **Review Failed Checks**
   - Fix test failures
   - Address security vulnerabilities
   - Improve code quality
   - Fix SLO violations

3. **Re-run Validation**
   ```bash
   ./scripts/validate-promotion-requirements.sh
   ```

### Promotion Stuck

1. **Check ArgoCD Status**
   ```bash
   argocd app get app-$TO_ENV
   ```

2. **Check GitOps Repository**
   - Verify changes were pushed
   - Check for merge conflicts

3. **Manual Intervention**
   ```bash
   # Manual sync
   argocd app sync app-$TO_ENV
   ```

### Approval Not Working

1. **Check Approval Configuration**
   - Verify promotion rules
   - Check approver permissions

2. **Bypass Approval (if authorized)**
   ```bash
   AUTO_APPROVE=true ./scripts/promote-environment.sh
   ```

## Best Practices

### 1. Start Small
- Promote to staging first
- Validate thoroughly
- Monitor closely

### 2. Use Canary
- Always use canary before production
- Monitor canary metrics
- Validate thoroughly

### 3. Set Appropriate Thresholds
- Base on historical data
- Consider business impact
- Review regularly

### 4. Monitor Closely
- Watch metrics after promotion
- Monitor error rates
- Track SLO compliance

### 5. Document Decisions
- Record promotion decisions
- Document threshold changes
- Share learnings

## Integration with CI/CD

### Pre-Promotion Check

Add to CI/CD pipeline:
```yaml
- name: Check Promotion Readiness
  run: |
    ./scripts/validate-promotion-requirements.sh
    if [ $? -ne 0 ]; then
      echo "Promotion requirements not met"
      exit 1
    fi
```

### Automated Promotion

For lower environments:
```yaml
- name: Auto-promote to Staging
  if: github.ref == 'refs/heads/main'
  run: |
    FROM_ENV=dev TO_ENV=staging ./scripts/promote-environment.sh
```

## References

- [Promotion Rules Configuration](../promotion/promotion-rules.yaml)
- [SLO and Error Budget Guide](./SLO_ERROR_BUDGET.md)
- [Automated Rollback Guide](./AUTOMATED_ROLLBACK.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
