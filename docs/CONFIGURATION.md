# Configuration Guide

## Overview

This guide covers all configuration options for the CI/CD pipeline, including environment variables, YAML configurations, and customization options.

## Table of Contents

- [GitHub Actions Configuration](#github-actions-configuration)
- [Kubernetes Configuration](#kubernetes-configuration)
- [ArgoCD Configuration](#argocd-configuration)
- [Monitoring Configuration](#monitoring-configuration)
- [Security Configuration](#security-configuration)
- [Promotion Configuration](#promotion-configuration)
- [SLO Configuration](#slo-configuration)
- [Environment Variables](#environment-variables)

## GitHub Actions Configuration

### Workflow File

**Location**: `.github/workflows/ci-cd-pipeline.yml`

### Key Configuration Options

#### Environment Variables

```yaml
env:
  NODE_VERSION: '20.x'      # Node.js version
  PYTHON_VERSION: '3.11'    # Python version
```

#### Job Dependencies

Jobs run in this order:
1. `build` - Builds application
2. `unit-tests` - Runs unit tests
3. `integration-tests` - Runs integration tests
4. `codeql-analysis` - CodeQL analysis
5. `secrets-scan` - Secrets detection
6. `security-scan` - Security scanning
7. `code-quality` - Code quality checks
8. `docker-build` - Docker image build
9. `container-scan` - Container scanning
10. `gitops-deploy` - GitOps deployment

#### Secrets Configuration

Required secrets in GitHub repository:

```yaml
secrets:
  GITOPS_REPO: "owner/gitops-repo"        # GitOps repository
  GITOPS_TOKEN: "ghp_xxxxx"                # GitHub token
  DOCKERHUB_USERNAME: "username"           # Optional
  DOCKERHUB_TOKEN: "xxxxx"                 # Optional
  SLACK_WEBHOOK: "https://..."             # Optional
  PAGERDUTY_KEY: "xxxxx"                   # Optional
  ARGOCD_SERVER: "argocd.example.com"      # Optional
  ARGOCD_PASSWORD: "xxxxx"                 # Optional
```

### Customization

#### Change Node.js Version

```yaml
env:
  NODE_VERSION: '18.x'  # Change to desired version
```

#### Change Python Version

```yaml
env:
  PYTHON_VERSION: '3.10'  # Change to desired version
```

#### Add Additional Test Stages

```yaml
jobs:
  e2e-tests:
    name: E2E Tests
    runs-on: ubuntu-latest
    needs: [integration-tests]
    steps:
      - name: Run E2E tests
        run: npm run test:e2e
```

## Kubernetes Configuration

### Base Manifests

**Location**: `k8s/base/`

#### Deployment Configuration

**File**: `k8s/base/deployment.yaml`

```yaml
spec:
  replicas: 2                    # Number of replicas
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: 100m              # CPU request
            memory: 128Mi          # Memory request
          limits:
            cpu: 500m              # CPU limit
            memory: 512Mi          # Memory limit
```

#### Service Configuration

**File**: `k8s/base/service.yaml`

```yaml
spec:
  type: ClusterIP                 # Service type
  ports:
  - port: 80                      # Service port
    targetPort: 8080              # Container port
```

#### HPA Configuration

**File**: `k8s/base/hpa.yaml`

```yaml
spec:
  minReplicas: 2                  # Minimum replicas
  maxReplicas: 10                 # Maximum replicas
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 70    # CPU target
```

### Environment Overlays

**Location**: `k8s/overlays/{env}/`

#### Dev Environment

**File**: `k8s/overlays/dev/kustomization.yaml`

```yaml
namespace: dev
replicas:
  - name: app
    count: 1                      # Dev: 1 replica
images:
  - name: ghcr.io/OWNER/REPO
    newTag: dev                   # Dev image tag
```

#### Production Environment

**File**: `k8s/overlays/prod/kustomization.yaml`

```yaml
namespace: production
replicas:
  - name: app
    count: 3                      # Prod: 3+ replicas
images:
  - name: ghcr.io/OWNER/REPO
    newTag: latest                 # Prod image tag
```

### Customization

#### Change Resource Limits

Edit `k8s/base/deployment.yaml`:

```yaml
resources:
  requests:
    cpu: 200m                      # Increase CPU request
    memory: 256Mi                  # Increase memory request
  limits:
    cpu: 1000m                     # Increase CPU limit
    memory: 1Gi                    # Increase memory limit
```

#### Change Replica Count

Edit environment-specific kustomization:

```yaml
# k8s/overlays/prod/kustomization.yaml
replicas:
  - name: app
    count: 5                       # Increase replicas
```

## ArgoCD Configuration

### Application Configuration

**Location**: `argocd/applications/`

#### Application Settings

**File**: `argocd/applications/app-prod.yaml`

```yaml
spec:
  source:
    repoURL: https://github.com/owner/repo
    targetRevision: main           # Branch to sync
    path: k8s/overlays/prod        # Path to manifests
  syncPolicy:
    automated:
      prune: true                  # Auto-prune
      selfHeal: true               # Self-healing
    syncOptions:
      - CreateNamespace=true       # Create namespace
```

### AppProject Configuration

**File**: `argocd/appproject.yaml`

```yaml
spec:
  sourceRepos:
    - '*'                          # Allow all repos
  destinations:
    - namespace: '*'               # Allow all namespaces
      server: https://kubernetes.default.svc
```

### Customization

#### Change Sync Policy

```yaml
syncPolicy:
  automated:
    prune: false                   # Disable auto-prune
    selfHeal: false                # Disable self-healing
  syncOptions:
    - CreateNamespace=false        # Don't create namespace
```

#### Add RBAC Rules

```yaml
roles:
  - name: developer
    policies:
      - p, proj:default:developer, applications, sync, default/*, allow
    groups:
      - developers
```

## Monitoring Configuration

### ServiceMonitor

**File**: `k8s/base/servicemonitor.yaml`

```yaml
spec:
  selector:
    matchLabels:
      app: app
  endpoints:
  - port: http
    interval: 30s                  # Scrape interval
    path: /metrics                  # Metrics path
```

### PrometheusRule

**File**: `k8s/base/prometheusrule-slo.yaml`

```yaml
spec:
  groups:
  - name: slo.availability
    interval: 5m                   # Rule evaluation interval
    rules:
    - alert: AvailabilitySLOBreach
      expr: |
        # Alert expression
      for: 5m                       # Alert duration
```

### Grafana Dashboards

**Location**: `monitoring/grafana-dashboard-*.json`

#### Customize Refresh Interval

```json
{
  "dashboard": {
    "refresh": "30s"                // Change refresh interval
  }
}
```

#### Add Custom Panels

```json
{
  "id": 11,
  "title": "Custom Metric",
  "type": "graph",
  "targets": [
    {
      "expr": "your_promql_query",
      "legendFormat": "Custom"
    }
  ]
}
```

## Security Configuration

### Gitleaks

**File**: `.gitleaks.toml`

```toml
[allowlist]
paths = [
    '''\.gitleaksignore''',
    '''test/.*''',
]

[[rules]]
id = "custom-rule"
description = "Custom secret pattern"
regex = '''your_regex_pattern'''
```

### TruffleHog

**File**: `.trufflehog.yaml`

```yaml
scan:
  scan_history: true                # Scan git history
  scan_uncommitted: true            # Scan uncommitted

filters:
  exclude_paths:
    - 'test/.*'                     # Exclude paths
  min_entropy: 3.0                  # Minimum entropy
```

### Pre-commit

**File**: `.pre-commit-config.yaml`

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0                    # Gitleaks version
    hooks:
      - id: gitleaks
        args: ['--verbose']         # Additional args
```

## Promotion Configuration

### Promotion Rules

**File**: `promotion/promotion-rules.yaml`

#### Change Coverage Requirements

```yaml
requirements:
  dev_to_staging:
    coverage:
      min_coverage: 75              # Increase from 70
      min_unit_coverage: 85         # Increase from 80
```

#### Change SLO Requirements

```yaml
requirements:
  staging_to_canary:
    slo:
      availability_min: 0.996       # Increase from 0.995
      error_rate_max: 0.004         # Decrease from 0.005
      latency_p95_max: 700           # Decrease from 800
```

#### Change Approval Requirements

```yaml
approvals:
  staging_to_canary:
    required: true
    approvers:
      - team: sre-team
        min_approvals: 2            # Increase from 1
```

### Rollback Policy

**File**: `slo/rollback-policy.yaml`

#### Change Thresholds

```yaml
triggers:
  error_budget:
    warning_threshold: 0.40         # Change from 0.50
    critical_threshold: 0.70        # Change from 0.80
    emergency_threshold: 0.90       # Change from 0.95
```

#### Change Cooldown Period

```yaml
safety:
  cooldown_period: 120              # Change from 60 minutes
  max_rollbacks_per_day: 5          # Change from 3
```

## SLO Configuration

### SLI/SLO Definitions

**File**: `slo/sli-slo-definitions.yaml`

#### Change Availability Target

```yaml
slis:
  - name: availability
    slo:
      target: 0.9995                # Change from 0.999 (99.95%)
      window: 30d
      error_budget: 0.0005         # Adjust error budget
```

#### Change Latency Targets

```yaml
slis:
  - name: latency-p95
    slo:
      target: 0.400                 # Change from 0.500 (400ms)
      window: 30d
      error_budget: 0.01
```

### Error Budget Policy

**File**: `slo/error-budget-policy.yaml`

#### Change Budget Allocation

```yaml
allocation:
  total_budget: 0.0005              # Change from 0.001 (0.05%)
  per_incident_max: 0.00005        # Change from 0.0001
  daily_burn_rate_limit: 0.000017  # Adjust daily limit
```

## Environment Variables

### Script Configuration

All scripts support environment variables for configuration:

#### Promotion Scripts

```bash
# promotion-environment.sh
FROM_ENV=dev
TO_ENV=staging
PROMETHEUS_URL=http://prometheus:9090
SERVICE_NAME=app
AUTO_APPROVE=false
DRY_RUN=false
```

#### SLO Scripts

```bash
# check-slo-compliance.sh
PROMETHEUS_URL=http://prometheus:9090
SERVICE_NAME=app
NAMESPACE=production
SLO_WINDOW=30d
ERROR_BUDGET=0.001
```

#### Rollback Scripts

```bash
# auto-rollback-on-error-budget.sh
PROMETHEUS_URL=http://prometheus:9090
SERVICE_NAME=app
GITOPS_REPO=owner/gitops-repo
GITOPS_TOKEN=ghp_xxxxx
ARGOCD_SERVER=argocd.example.com
ARGOCD_PASSWORD=xxxxx
ROLLBACK_ENABLED=true
AUTO_ROLLBACK_CRITICAL=true
```

### Kubernetes Environment Variables

Set in deployment manifests:

```yaml
env:
  - name: ENVIRONMENT
    value: "production"
  - name: LOG_LEVEL
    value: "info"
  - name: METRICS_ENABLED
    value: "true"
```

## Advanced Configuration

### Custom Metrics

Add custom metrics to ServiceMonitor:

```yaml
endpoints:
  - port: http
    path: /metrics
  - port: http
    path: /custom-metrics      # Custom metrics endpoint
```

### Custom Alerts

Add custom alerts to PrometheusRule:

```yaml
groups:
  - name: custom.alerts
    rules:
      - alert: CustomAlert
        expr: your_promql_query
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Custom alert"
```

### Custom Dashboards

Create custom Grafana dashboard:

```json
{
  "dashboard": {
    "title": "Custom Dashboard",
    "panels": [
      {
        "title": "Custom Panel",
        "targets": [
          {
            "expr": "your_promql_query"
          }
        ]
      }
    ]
  }
}
```

## Configuration Best Practices

### 1. Use Environment-Specific Values

- Keep base manifests generic
- Use overlays for environment-specific values
- Don't hardcode values in base

### 2. Version Control Everything

- Commit all configuration files
- Use Git for configuration history
- Tag configuration versions

### 3. Document Changes

- Add comments to complex configurations
- Update documentation when changing defaults
- Keep changelog of configuration changes

### 4. Test Configuration Changes

- Test in dev environment first
- Validate YAML syntax
- Check for breaking changes

### 5. Use Secrets Management

- Never commit secrets
- Use Sealed Secrets or External Secrets
- Rotate secrets regularly

## Troubleshooting Configuration

### Validate YAML

```bash
# Validate Kubernetes manifests
kubectl apply --dry-run=client -f k8s/base/

# Validate with kustomize
kubectl kustomize k8s/overlays/dev

# Validate YAML syntax
yamllint k8s/**/*.yaml
```

### Check Configuration

```bash
# Check ArgoCD application config
argocd app get app-prod -o yaml

# Check PrometheusRule
kubectl get prometheusrule -n monitoring -o yaml

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring -o yaml
```

### Common Issues

1. **Invalid YAML**: Use yamllint to validate
2. **Missing Secrets**: Check secret existence
3. **Wrong Image Tag**: Verify in kustomization
4. **Incorrect Selectors**: Check label matching

## Configuration Reference

### Quick Reference

| Component | Configuration File | Key Settings |
|-----------|-------------------|--------------|
| CI/CD | `.github/workflows/ci-cd-pipeline.yml` | Node/Python versions, job dependencies |
| Kubernetes | `k8s/base/*.yaml` | Resources, replicas, probes |
| ArgoCD | `argocd/applications/*.yaml` | Sync policy, source paths |
| Monitoring | `k8s/base/servicemonitor.yaml` | Scrape intervals, endpoints |
| Alerts | `k8s/base/prometheusrule-*.yaml` | Alert expressions, thresholds |
| Promotion | `promotion/promotion-rules.yaml` | Requirements, approvals |
| SLO | `slo/sli-slo-definitions.yaml` | Targets, error budgets |
| Security | `.gitleaks.toml`, `.trufflehog.yaml` | Rules, exclusions |

## Next Steps

- Review [SETUP.md](./SETUP.md) for initial configuration
- Review [USAGE.md](./USAGE.md) for usage examples
- Review [ARCHITECTURE.md](./ARCHITECTURE.md) for system design
