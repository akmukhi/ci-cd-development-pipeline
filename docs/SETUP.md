# Setup Guide

## Overview

This guide will help you set up the complete CI/CD development pipeline with all its components, including GitHub Actions workflows, Kubernetes deployments, ArgoCD, monitoring, and security scanning.

## Prerequisites

### Required Tools

- **Git** (2.30+)
- **kubectl** (1.24+)
- **Docker** (20.10+) or **Podman** (4.0+)
- **Helm** (3.8+) - for installing ArgoCD
- **jq** - for JSON processing
- **yq** - for YAML processing
- **bc** - for calculations
- **curl** - for API calls

### Required Services

- **Kubernetes Cluster** (1.24+)
  - Access to create namespaces, deployments, services
  - RBAC permissions configured
  - Ingress controller installed (nginx recommended)
  - Cert-manager for TLS certificates (optional)

- **GitHub Repository**
  - Repository with code
  - GitHub Actions enabled
  - Secrets configured

- **Container Registry**
  - GitHub Container Registry (ghcr.io) or Docker Hub
  - Push/pull permissions

- **GitOps Repository** (optional but recommended)
  - Separate repository for Kubernetes manifests
  - Write access for CI/CD pipeline

## Step-by-Step Setup

### 1. Repository Setup

#### Clone the Repository

```bash
git clone https://github.com/your-org/ci-cd-development-pipeline.git
cd ci-cd-development-pipeline
```

#### Configure Repository Settings

1. Update image references in Kubernetes manifests:
   ```bash
   # Replace OWNER/REPO with your organization/repository
   find k8s/ -type f -name "*.yaml" -exec sed -i 's/OWNER\/REPO/your-org\/your-repo/g' {} \;
   ```

2. Update domain names in Ingress configurations:
   ```bash
   # Replace example.com with your domain
   find k8s/ -type f -name "*.yaml" -exec sed -i 's/example\.com/your-domain.com/g' {} \;
   ```

### 2. GitHub Actions Setup

#### Configure GitHub Secrets

Go to your repository Settings > Secrets and variables > Actions, and add:

**Required Secrets:**
- `GITOPS_REPO`: Your GitOps repository (e.g., `owner/gitops-repo`)
- `GITOPS_TOKEN`: GitHub token with write access to GitOps repo
- `DOCKERHUB_USERNAME`: Docker Hub username (optional)
- `DOCKERHUB_TOKEN`: Docker Hub access token (optional)

**Optional Secrets:**
- `SLACK_WEBHOOK`: Slack webhook URL for notifications
- `PAGERDUTY_KEY`: PagerDuty integration key
- `ARGOCD_SERVER`: ArgoCD server URL
- `ARGOCD_PASSWORD`: ArgoCD admin password

#### Enable GitHub Actions

1. Go to repository Settings > Actions > General
2. Enable "Allow all actions and reusable workflows"
3. Enable "Read and write permissions" for workflows

### 3. Kubernetes Cluster Setup

#### Create Namespaces

```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace production
kubectl create namespace monitoring
kubectl create namespace argocd
```

#### Install ArgoCD

```bash
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### Install Prometheus Operator

```bash
# Add Prometheus Operator Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d
```

#### Install Grafana (if not included with Prometheus)

```bash
# Grafana is usually included with kube-prometheus-stack
# Access Grafana UI
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Default credentials: admin / prom-operator
```

### 4. Configure Monitoring

#### Apply ServiceMonitor

```bash
kubectl apply -f k8s/base/servicemonitor.yaml
```

#### Apply PrometheusRules

```bash
kubectl apply -f k8s/base/prometheusrule.yaml
kubectl apply -f k8s/base/prometheusrule-slo.yaml
kubectl apply -f k8s/monitoring/prometheusrule-comprehensive.yaml
kubectl apply -f k8s/monitoring/prometheusrule-rollback.yaml
```

#### Import Grafana Dashboards

```bash
# Method 1: Via Grafana API
GRAFANA_URL="http://grafana:3000"
GRAFANA_API_KEY="your-api-key"

curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -d @monitoring/grafana-dashboard-app.json \
  "$GRAFANA_URL/api/dashboards/db"

curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GRAFANA_API_KEY" \
  -d @monitoring/grafana-dashboard-slo.json \
  "$GRAFANA_URL/api/dashboards/db"

# Method 2: Via UI
# 1. Go to Grafana UI
# 2. Navigate to Dashboards > Import
# 3. Upload monitoring/grafana-dashboard-app.json
# 4. Upload monitoring/grafana-dashboard-slo.json
```

### 5. Configure ArgoCD Applications

#### Create AppProject

```bash
kubectl apply -f argocd/appproject.yaml
```

#### Create Applications

```bash
# Update repository URLs in application manifests
sed -i 's|https://github.com/OWNER/ci-cd-development-pipeline|https://github.com/your-org/your-repo|g' argocd/applications/*.yaml

# Apply applications
kubectl apply -f argocd/applications/app-dev.yaml
kubectl apply -f argocd/applications/app-staging.yaml
kubectl apply -f argocd/applications/app-canary.yaml
kubectl apply -f argocd/applications/app-prod.yaml
```

### 6. Setup Pre-commit Hooks

#### Install Pre-commit

```bash
pip install pre-commit
```

#### Install Hooks

```bash
pre-commit install
pre-commit install --hook-type pre-push
```

#### Test Hooks

```bash
pre-commit run --all-files
```

### 7. Configure Secrets Detection

#### Gitleaks Configuration

The `.gitleaks.toml` file is already configured. Customize if needed:

```bash
# Review and update .gitleaks.toml
cat .gitleaks.toml

# Add custom ignore patterns to .gitleaksignore
echo "**/custom-path/**" >> .gitleaksignore
```

#### TruffleHog Configuration

The `.trufflehog.yaml` file is already configured. Customize if needed:

```bash
# Review and update .trufflehog.yaml
cat .trufflehog.yaml
```

### 8. Setup Error Budget Monitoring

#### Create Monitoring Secrets

```bash
# GitOps credentials
kubectl create secret generic gitops-credentials \
  --from-literal=repo=owner/gitops-repo \
  --from-literal=token=ghp_xxxxx \
  -n monitoring

# ArgoCD credentials
kubectl create secret generic argocd-credentials \
  --from-literal=server=argocd-server.argocd.svc.cluster.local:443 \
  --from-literal=app-name=app-prod \
  --from-literal=password=xxxxx \
  -n monitoring

# Notification credentials (optional)
kubectl create secret generic notification-credentials \
  --from-literal=slack-webhook=https://hooks.slack.com/services/xxx \
  --from-literal=pagerduty-key=xxxxx \
  -n monitoring
```

#### Deploy Error Budget Monitor

```bash
# Update scripts ConfigMap (if needed)
kubectl create configmap rollback-scripts \
  --from-file=scripts/auto-rollback-on-error-budget.sh \
  --from-file=scripts/rollback-gitops-manifest.sh \
  --from-file=scripts/rollback-argocd-app.sh \
  -n monitoring

# Apply CronJob
kubectl apply -f k8s/monitoring/error-budget-rollback-job.yaml
```

### 9. Verify Setup

#### Check GitHub Actions

1. Go to repository Actions tab
2. Verify workflows are visible
3. Trigger a test workflow run

#### Check Kubernetes Resources

```bash
# Check namespaces
kubectl get namespaces

# Check ArgoCD
kubectl get pods -n argocd
kubectl get svc -n argocd

# Check Prometheus
kubectl get pods -n monitoring
kubectl get servicemonitor -n monitoring
kubectl get prometheusrule -n monitoring

# Check applications
kubectl get applications -n argocd
```

#### Check Monitoring

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Port forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Access UIs
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/prom-operator)
```

### 10. Initial Deployment

#### Deploy to Dev Environment

```bash
# Via ArgoCD UI
# 1. Go to ArgoCD UI
# 2. Select app-dev application
# 3. Click Sync

# Or via CLI
argocd app sync app-dev
```

#### Verify Deployment

```bash
# Check pods
kubectl get pods -n dev

# Check services
kubectl get svc -n dev

# Check ingress
kubectl get ingress -n dev

# Test application
curl http://app-dev.your-domain.com/health
```

## Post-Setup Configuration

### Customize SLO Targets

Edit `slo/sli-slo-definitions.yaml` to adjust SLO targets:

```yaml
slo:
  target: 0.999  # 99.9% availability
  window: 30d
  error_budget: 0.001
```

### Customize Promotion Rules

Edit `promotion/promotion-rules.yaml` to adjust promotion requirements:

```yaml
requirements:
  dev_to_staging:
    coverage:
      min_coverage: 70
```

### Configure Notifications

Update notification channels in:
- `slo/error-budget-policy.yaml`
- `slo/rollback-policy.yaml`
- GitHub Actions workflow files

## Troubleshooting

### GitHub Actions Not Running

1. Check repository settings:
   - Actions enabled
   - Workflow permissions configured
   - Secrets are set

2. Check workflow syntax:
   ```bash
   # Validate YAML
   yamllint .github/workflows/*.yml
   ```

### ArgoCD Not Syncing

1. Check ArgoCD application status:
   ```bash
   argocd app get app-dev
   ```

2. Check repository access:
   - Verify repository URL is correct
   - Check token has read access
   - Verify branch exists

3. Check ArgoCD logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
   ```

### Prometheus Not Scraping

1. Check ServiceMonitor:
   ```bash
   kubectl describe servicemonitor app -n monitoring
   ```

2. Check Prometheus targets:
   - Go to Prometheus UI
   - Navigate to Status > Targets
   - Verify endpoints are up

3. Check pod labels:
   ```bash
   kubectl get pods -n dev --show-labels
   # Ensure labels match ServiceMonitor selector
   ```

### Metrics Not Appearing

1. Verify application exposes metrics:
   ```bash
   kubectl port-forward -n dev svc/app 8080:80
   curl http://localhost:8080/metrics
   ```

2. Check ServiceMonitor configuration:
   ```bash
   kubectl get servicemonitor app -n monitoring -o yaml
   ```

## Next Steps

1. **Review Documentation**:
   - [USAGE.md](./USAGE.md) - How to use the pipeline
   - [ARCHITECTURE.md](./ARCHITECTURE.md) - Architecture overview
   - [CONFIGURATION.md](./CONFIGURATION.md) - Configuration guide

2. **Customize for Your Needs**:
   - Update SLO targets
   - Adjust promotion rules
   - Configure notifications
   - Add custom metrics

3. **Monitor and Iterate**:
   - Review Grafana dashboards
   - Check alert effectiveness
   - Adjust thresholds based on data
   - Update runbooks

## Support

For issues or questions:
- Check [Troubleshooting](#troubleshooting) section
- Review [ARCHITECTURE.md](./ARCHITECTURE.md) for system design
- Check GitHub Issues
- Contact SRE team
