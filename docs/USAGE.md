# Usage Guide

## Overview

This guide explains how to use the CI/CD development pipeline for building, testing, deploying, and monitoring your applications.

## Table of Contents

- [Daily Development Workflow](#daily-development-workflow)
- [Running Tests](#running-tests)
- [Deploying Applications](#deploying-applications)
- [Environment Promotion](#environment-promotion)
- [Monitoring and Observability](#monitoring-and-observability)
- [Security Scanning](#security-scanning)
- [Error Budget Management](#error-budget-management)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

## Daily Development Workflow

### 1. Pre-commit Checks

Before committing code, pre-commit hooks automatically run:

```bash
# Hooks run automatically on commit
git add .
git commit -m "Add new feature"
# Pre-commit hooks run automatically

# Or run manually
pre-commit run --all-files
```

**What runs:**
- Gitleaks (secrets detection)
- TruffleHog (secrets detection)
- YAML/JSON validation
- Trailing whitespace removal
- Large file detection
- Private key detection

### 2. Push to Repository

```bash
git push origin feature-branch
```

**What happens:**
- GitHub Actions workflow triggers
- Build and test stages run
- Security scans execute
- Code quality checks run
- Results reported in GitHub UI

### 3. Create Pull Request

```bash
# Create PR via GitHub CLI
gh pr create --title "Add new feature" --body "Description"

# Or via GitHub UI
# 1. Go to repository
# 2. Click "New Pull Request"
# 3. Select branches
# 4. Add description
```

**What happens:**
- All CI checks run
- Security scans on PR
- Coverage reports generated
- PR comments with results

## Running Tests

### Local Testing

```bash
# Run unit tests
npm test
# or
pytest tests/unit/

# Run integration tests
npm run test:integration
# or
pytest tests/integration/

# Run with coverage
npm test -- --coverage
# or
pytest --cov=. --cov-report=html
```

### CI/CD Testing

Tests run automatically in GitHub Actions:

1. **Unit Tests**: Run on every push and PR
2. **Integration Tests**: Run with service containers (PostgreSQL, Redis)
3. **Coverage Reports**: Generated and uploaded as artifacts

**View Results:**
- GitHub Actions tab → Select workflow run → View test results
- Download coverage artifacts
- View coverage in PR comments

## Deploying Applications

### Automatic Deployment

Deployments happen automatically based on branch:

- **Push to `main`**: Deploys to production (after canary)
- **Push to `develop`**: Deploys to staging
- **Pull Request**: Builds and tests only (no deployment)

### Manual Deployment

#### Via ArgoCD UI

1. Access ArgoCD UI:
   ```bash
   kubectl port-forward -n argocd svc/argocd-server 8080:443
   # Open https://localhost:8080
   ```

2. Select application (e.g., `app-dev`)
3. Click "Sync"
4. Select sync options
5. Click "Synchronize"

#### Via ArgoCD CLI

```bash
# Login
argocd login argocd-server.argocd.svc.cluster.local:443

# Sync application
argocd app sync app-dev

# Watch sync status
argocd app wait app-dev

# Get application status
argocd app get app-dev
```

#### Via GitOps

```bash
# Update image tag in kustomization
cd k8s/overlays/dev
sed -i 's/newTag:.*/newTag: v1.2.3/' kustomization.yaml

# Commit and push
git add kustomization.yaml
git commit -m "Deploy v1.2.3 to dev"
git push origin main

# ArgoCD will auto-sync (if enabled)
```

### Deployment Verification

```bash
# Check deployment status
kubectl get deployments -n dev
kubectl get pods -n dev
kubectl get svc -n dev

# Check application health
curl http://app-dev.your-domain.com/health
curl http://app-dev.your-domain.com/ready

# View logs
kubectl logs -n dev -l app=app --tail=100 -f
```

## Environment Promotion

### Promotion Process

Promotions follow: **Dev → Staging → Canary → Production**

### Validate Promotion Readiness

```bash
# Check if ready for promotion
FROM_ENV=dev TO_ENV=staging ./scripts/validate-promotion-requirements.sh
```

**Checks:**
- Tests passed
- Coverage meets threshold
- Security scans passed
- SLO compliance
- Error budget OK
- No critical alerts

### Promote Environment

#### Via Script

```bash
# Promote dev to staging
FROM_ENV=dev TO_ENV=staging ./scripts/promote-environment.sh

# Promote staging to canary (requires approval)
FROM_ENV=staging TO_ENV=canary ./scripts/promote-environment.sh

# Promote with auto-approve
FROM_ENV=canary TO_ENV=production AUTO_APPROVE=true ./scripts/promote-environment.sh
```

#### Via GitHub Actions

```bash
# Trigger promotion workflow
gh workflow run promotion-workflow.yml \
  -f from_env=staging \
  -f to_env=canary \
  -f auto_approve=false
```

#### Promotion Requirements

**Dev → Staging:**
- ✅ Tests passed
- ✅ Coverage ≥ 70%
- ✅ Security: Max 5 high, 0 critical
- ✅ SLO: 99% availability
- ⚠️ Approval: Not required

**Staging → Canary:**
- ✅ All tests + E2E
- ✅ Coverage ≥ 80%
- ✅ Security: Max 0 high, 0 critical
- ✅ SLO: 99.5% availability
- ⚠️ Approval: SRE + QA required

**Canary → Production:**
- ✅ All tests + Performance
- ✅ Coverage ≥ 85%
- ✅ Security: Max 0 high, 0 critical
- ✅ SLO: 99.9% availability
- ✅ Canary: 10% traffic, 24h, 99% success
- ⚠️ Approval: SRE + Engineering Lead + Product Owner

## Monitoring and Observability

### Access Dashboards

#### Grafana

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Access: http://localhost:3000
# Default: admin / prom-operator
```

**Available Dashboards:**
- Application Monitoring
- SLO & Error Budget
- Canary Deployment Monitoring

#### Prometheus

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Access: http://localhost:9090
```

**Useful Queries:**
- Request rate: `sum(rate(http_requests_total{service="app"}[5m]))`
- Error rate: `sum(rate(http_requests_total{service="app",status=~"4..|5.."}[5m])) / sum(rate(http_requests_total{service="app"}[5m]))`
- P95 latency: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="app"}[5m])) by (le))`

### Check SLO Compliance

```bash
# Run SLO compliance check
./scripts/check-slo-compliance.sh

# Generate SLO report
./scripts/generate-slo-report.sh
# Output: slo-report-YYYYMMDD-HHMMSS.json
```

### Monitor Error Budget

```bash
# Check error budget consumption
./scripts/check-error-budget.sh

# Output includes:
# - Current consumption
# - Burn rates
# - Time until exhaustion
# - Recommended actions
```

## Security Scanning

### Pre-commit Scanning

Runs automatically on commit:

```bash
git commit -m "Add feature"
# Gitleaks and TruffleHog run automatically
```

### CI/CD Scanning

Scans run automatically in GitHub Actions:

1. **Gitleaks**: Scans repository for secrets
2. **TruffleHog**: Detects secrets and credentials
3. **Trivy**: Scans filesystem, repository, and config
4. **CodeQL**: Static code analysis
5. **npm audit**: Dependency vulnerabilities
6. **Bandit**: Python security linting

**View Results:**
- GitHub Security tab
- GitHub Actions artifacts
- SARIF uploads to GitHub Security

### Manual Scanning

```bash
# Run Gitleaks locally
gitleaks detect --verbose --redact

# Run TruffleHog locally
trufflehog git file://. --json

# Run Trivy
trivy fs .
trivy repo .
trivy config .
```

## Error Budget Management

### Check Error Budget Status

```bash
# Quick check
./scripts/check-error-budget.sh

# Detailed report
./scripts/generate-slo-report.sh
```

### Error Budget Thresholds

- **50%**: Warning - Monitor closely
- **80%**: Critical - Consider freezing deployments
- **95%**: Emergency - Freeze all deployments

### Automated Rollback

Rollback triggers automatically when:
- Error budget ≥ 95% consumed
- Error budget ≥ 80% consumed (if auto-rollback enabled)
- SLO violations detected

**Monitor Rollback:**
```bash
# Check rollback job logs
kubectl logs -n monitoring -l app=error-budget-monitor --tail=100

# Check GitOps repository for rollback commits
git log --oneline --grep="Rollback"
```

## Rollback Procedures

### Automatic Rollback

Happens automatically when error budget thresholds are breached.

### Manual Rollback

#### Rollback GitOps

```bash
# Rollback to previous commit
./scripts/rollback-gitops-manifest.sh

# Rollback to specific commit
TARGET_COMMIT=abc123 ./scripts/rollback-gitops-manifest.sh
```

#### Rollback ArgoCD

```bash
# Rollback to previous revision
./scripts/rollback-argocd-app.sh

# Rollback to specific revision
TARGET_REVISION=abc123 ./scripts/rollback-argocd-app.sh
```

#### Rollback via ArgoCD UI

1. Go to ArgoCD UI
2. Select application
3. Click "History"
4. Select previous revision
5. Click "Rollback"

#### Rollback via kubectl

```bash
# Rollback deployment
kubectl rollout undo deployment/app -n production

# Check rollout status
kubectl rollout status deployment/app -n production

# View rollout history
kubectl rollout history deployment/app -n production
```

### Canary Rollback

```bash
# Rollback canary deployment
kubectl argo rollouts undo canary-app -n production

# Or use script
./scripts/canary-rollback.sh
```

## Troubleshooting

### Pipeline Failing

1. **Check GitHub Actions logs**:
   - Go to Actions tab
   - Select failed workflow
   - Review error messages

2. **Common issues**:
   - Test failures: Fix tests
   - Security findings: Remove secrets
   - Build errors: Check Dockerfile
   - Deployment failures: Check Kubernetes resources

### Deployment Not Working

1. **Check ArgoCD status**:
   ```bash
   argocd app get app-dev
   ```

2. **Check Kubernetes resources**:
   ```bash
   kubectl get pods -n dev
   kubectl describe pod <pod-name> -n dev
   kubectl logs <pod-name> -n dev
   ```

3. **Check ingress**:
   ```bash
   kubectl get ingress -n dev
   kubectl describe ingress app -n dev
   ```

### Metrics Not Showing

1. **Check ServiceMonitor**:
   ```bash
   kubectl get servicemonitor -n monitoring
   kubectl describe servicemonitor app -n monitoring
   ```

2. **Check Prometheus targets**:
   - Go to Prometheus UI
   - Status > Targets
   - Verify endpoints are up

3. **Check application metrics endpoint**:
   ```bash
   kubectl port-forward -n dev svc/app 8080:80
   curl http://localhost:8080/metrics
   ```

### Alerts Not Firing

1. **Check PrometheusRule**:
   ```bash
   kubectl get prometheusrule -n monitoring
   kubectl describe prometheusrule comprehensive-alerts -n monitoring
   ```

2. **Test alert expression**:
   - Go to Prometheus UI
   - Run alert query
   - Verify results

3. **Check Alertmanager**:
   ```bash
   kubectl get pods -n monitoring -l app=alertmanager
   kubectl logs -n monitoring -l app=alertmanager
   ```

## Best Practices

### Development

1. **Run pre-commit hooks** before committing
2. **Write tests** for new features
3. **Check security scans** before pushing
4. **Review PR** before merging

### Deployment

1. **Test in dev** first
2. **Promote gradually** through environments
3. **Monitor closely** after deployment
4. **Have rollback plan** ready

### Monitoring

1. **Check dashboards** regularly
2. **Review alerts** and adjust thresholds
3. **Track SLO compliance** weekly
4. **Review error budget** before deployments

### Security

1. **Never commit secrets**
2. **Use secret management** (Sealed Secrets, External Secrets)
3. **Review security scans** regularly
4. **Update dependencies** frequently

## Quick Reference

### Common Commands

```bash
# Check SLO compliance
./scripts/check-slo-compliance.sh

# Check error budget
./scripts/check-error-budget.sh

# Promote environment
FROM_ENV=dev TO_ENV=staging ./scripts/promote-environment.sh

# Rollback
./scripts/rollback-argocd-app.sh

# Validate promotion
FROM_ENV=staging TO_ENV=canary ./scripts/validate-promotion-requirements.sh
```

### Useful kubectl Commands

```bash
# Get pods
kubectl get pods -n <namespace>

# View logs
kubectl logs -n <namespace> -l app=app --tail=100 -f

# Describe resource
kubectl describe deployment app -n <namespace>

# Port forward
kubectl port-forward -n <namespace> svc/app 8080:80
```

### Useful ArgoCD Commands

```bash
# List applications
argocd app list

# Get application
argocd app get app-dev

# Sync application
argocd app sync app-dev

# Watch application
argocd app wait app-dev
```

## Getting Help

- **Documentation**: Check [ARCHITECTURE.md](./ARCHITECTURE.md) and [CONFIGURATION.md](./CONFIGURATION.md)
- **Issues**: Check GitHub Issues
- **Team**: Contact SRE team
- **Runbooks**: Check alert annotations for runbook URLs
