# CI/CD Development Pipeline

A comprehensive, production-ready CI/CD pipeline with automated testing, security scanning, GitOps deployments, canary rollouts, SLO monitoring, and error budget management.

## 🚀 Features

### CI/CD Pipeline
- ✅ **Multi-stage Build & Test**: Unit and integration tests with coverage reporting
- ✅ **Multi-Architecture Docker Builds**: Support for linux/amd64 and linux/arm64
- ✅ **Security Scanning**: Gitleaks, TruffleHog, CodeQL, Trivy (filesystem, repo, config, container)
- ✅ **Code Quality Checks**: ESLint, Prettier, Black, Pylint
- ✅ **Automated GitOps Deployment**: ArgoCD integration with automatic sync
- ✅ **Pre-commit Hooks**: Secrets detection and code quality checks before commit

### Deployment Strategies
- ✅ **Canary Deployments**: Progressive traffic rollout (10% → 25% → 50% → 75% → 100%)
- ✅ **Automated Analysis**: Metrics-based promotion and rollback
- ✅ **Multi-Environment Support**: Dev, Staging, Canary, Production
- ✅ **Environment Promotion**: Automated promotion with validation and approvals
- ✅ **Rollback Automation**: Automatic rollback on error budget threshold breach

### Monitoring & Observability
- ✅ **Prometheus Metrics**: Comprehensive application and infrastructure metrics
- ✅ **Grafana Dashboards**: Application monitoring and SLO tracking dashboards
- ✅ **SLO Management**: Service Level Objectives with error budget tracking
- ✅ **Alerting Rules**: Prometheus-based alerting for critical issues
- ✅ **Error Budget Monitoring**: Real-time error budget consumption tracking

### Security
- ✅ **Secrets Detection**: Gitleaks and TruffleHog integration
- ✅ **Vulnerability Scanning**: Trivy for filesystem, repository, and container scanning
- ✅ **Static Analysis**: CodeQL for security and quality analysis
- ✅ **Dependency Scanning**: npm audit and Safety for dependency vulnerabilities
- ✅ **Policy Enforcement**: OPA (Open Policy Agent) for policy validation

### GitOps
- ✅ **Kustomize-based Manifests**: Base/overlay structure for multi-environment
- ✅ **ArgoCD Integration**: Automated application sync and management
- ✅ **Multi-Environment Manifests**: Separate configs for dev/staging/canary/prod
- ✅ **Automated Rollback**: GitOps manifest reversion on errors

## 📋 Quick Start

### Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured
- GitHub repository with Actions enabled
- Container registry access (GHCR or Docker Hub)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-org/ci-cd-development-pipeline.git
   cd ci-cd-development-pipeline
   ```

2. **Configure GitHub Secrets**:
   - Go to repository Settings > Secrets and variables > Actions
   - Add required secrets (see [SETUP.md](./docs/SETUP.md))

3. **Setup Kubernetes**:
   ```bash
   # Create namespaces
   kubectl create namespace dev staging production monitoring argocd
   
   # Install ArgoCD
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd --namespace argocd --create-namespace
   
   # Install Prometheus
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
   ```

4. **Apply Kubernetes Manifests**:
   ```bash
   # Apply base manifests
   kubectl apply -k k8s/base/
   
   # Apply environment overlays
   kubectl apply -k k8s/overlays/dev/
   ```

5. **Setup ArgoCD Applications**:
   ```bash
   kubectl apply -f argocd/applications/
   ```

For detailed setup instructions, see [SETUP.md](./docs/SETUP.md).

## 🎯 Usage

### Daily Development

```bash
# Install pre-commit hooks
pre-commit install

# Make changes and commit
git add .
git commit -m "Add feature"
# Pre-commit hooks run automatically (secrets detection, code quality)

# Push to trigger CI/CD
git push origin feature-branch
```

### Deploy to Environment

**Automatic Deployment**:
- Push to `main` → Deploys to production (via canary)
- Push to `develop` → Deploys to staging
- Pull Request → Builds and tests only

**Manual Deployment via ArgoCD**:
```bash
# Sync application
argocd app sync app-dev

# Or via UI
# 1. Access ArgoCD UI
# 2. Select application
# 3. Click Sync
```

### Promote Between Environments

```bash
# Validate promotion readiness
FROM_ENV=dev TO_ENV=staging ./scripts/validate-promotion-requirements.sh

# Promote environment
FROM_ENV=dev TO_ENV=staging ./scripts/promote-environment.sh

# Or via GitHub Actions
gh workflow run promotion-workflow.yml -f from_env=staging -f to_env=canary
```

### Monitor Application

```bash
# Check SLO compliance
./scripts/check-slo-compliance.sh

# Check error budget
./scripts/check-error-budget.sh

# Generate SLO report
./scripts/generate-slo-report.sh
```

### Rollback

**Automatic Rollback**:
- Triggers when error budget ≥ 95% consumed
- Or when error budget ≥ 80% consumed (if enabled)

**Manual Rollback**:
```bash
# Rollback ArgoCD application
./scripts/rollback-argocd-app.sh

# Rollback GitOps manifest
./scripts/rollback-gitops-manifest.sh

# Rollback canary deployment
kubectl argo rollouts undo canary-app -n production
```

For detailed usage instructions, see [USAGE.md](./docs/USAGE.md).

## 📊 Monitoring Dashboards

### Access Dashboards

**Grafana**:
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000 (admin/prom-operator)
```

**Prometheus**:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Access: http://localhost:9090
```

### Available Dashboards

- **Application Monitoring**: Request rates, error rates, latency, resource usage
- **SLO & Error Budget**: Availability trends, error budget consumption, burn rates
- **Canary Deployment**: Traffic split, canary vs stable comparison

## 🔒 Security Features

### Pre-commit Security

Automatically runs on every commit:
- **Gitleaks**: Detects secrets and credentials
- **TruffleHog**: Scans for exposed secrets
- **File Checks**: Detects private keys, large files

### CI/CD Security Scanning

Runs in GitHub Actions:
- **Gitleaks**: Repository-wide secrets scan
- **TruffleHog**: Git history secrets scan
- **CodeQL**: Static security analysis
- **Trivy**: Filesystem, repository, config, and container scanning
- **npm audit**: Dependency vulnerability scanning
- **Bandit**: Python security linting

### Results

- Findings uploaded to GitHub Security tab
- SARIF reports for integration
- Artifacts available for download
- PR comments with scan results

## 🎛️ Configuration

### Key Configuration Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci-cd-pipeline.yml` | CI/CD pipeline definition |
| `k8s/base/` | Base Kubernetes manifests |
| `k8s/overlays/{env}/` | Environment-specific configurations |
| `promotion/promotion-rules.yaml` | Environment promotion rules |
| `slo/sli-slo-definitions.yaml` | SLO and error budget definitions |
| `.gitleaks.toml` | Gitleaks configuration |
| `.trufflehog.yaml` | TruffleHog configuration |
| `.pre-commit-config.yaml` | Pre-commit hooks configuration |

### Customization

**Change SLO Targets**:
```yaml
# slo/sli-slo-definitions.yaml
slo:
  target: 0.999  # 99.9% availability
  error_budget: 0.001
```

**Adjust Promotion Requirements**:
```yaml
# promotion/promotion-rules.yaml
requirements:
  dev_to_staging:
    coverage:
      min_coverage: 75  # Increase from 70
```

**Modify Resource Limits**:
```yaml
# k8s/base/deployment.yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
```

For complete configuration guide, see [CONFIGURATION.md](./docs/CONFIGURATION.md).

## 🏗️ Architecture

### Pipeline Flow

```
Developer → GitHub → GitHub Actions → Build/Test/Scan → 
Container Registry → GitOps Repo → ArgoCD → Kubernetes → 
Prometheus → Grafana
```

### Key Components

- **GitHub Actions**: CI/CD orchestration
- **ArgoCD**: GitOps continuous delivery
- **Kubernetes**: Container orchestration
- **Prometheus**: Metrics collection
- **Grafana**: Visualization
- **Istio**: Service mesh for canary deployments
- **Argo Rollouts**: Advanced deployment strategies

For detailed architecture, see [ARCHITECTURE.md](./docs/ARCHITECTURE.md).

## 📚 Documentation

- **[SETUP.md](./docs/SETUP.md)**: Complete setup guide
- **[USAGE.md](./docs/USAGE.md)**: Usage instructions and examples
- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)**: System architecture and design
- **[CONFIGURATION.md](./docs/CONFIGURATION.md)**: Configuration reference
- **[SLO_ERROR_BUDGET.md](./docs/SLO_ERROR_BUDGET.md)**: SLO and error budget guide
- **[CANARY_DEPLOYMENT.md](./docs/CANARY_DEPLOYMENT.md)**: Canary deployment guide
- **[AUTOMATED_ROLLBACK.md](./docs/AUTOMATED_ROLLBACK.md)**: Rollback automation guide
- **[ENVIRONMENT_PROMOTION.md](./docs/ENVIRONMENT_PROMOTION.md)**: Environment promotion guide
- **[MONITORING_AND_ALERTING.md](./docs/MONITORING_AND_ALERTING.md)**: Monitoring and alerting guide

## 🛠️ Scripts

### Available Scripts

| Script | Purpose |
|-------|---------|
| `scripts/check-slo-compliance.sh` | Check SLO compliance |
| `scripts/check-error-budget.sh` | Monitor error budget |
| `scripts/generate-slo-report.sh` | Generate SLO report |
| `scripts/promote-environment.sh` | Promote between environments |
| `scripts/validate-promotion-requirements.sh` | Validate promotion readiness |
| `scripts/rollback-argocd-app.sh` | Rollback ArgoCD application |
| `scripts/rollback-gitops-manifest.sh` | Rollback GitOps manifest |
| `scripts/auto-rollback-on-error-budget.sh` | Automatic rollback on error budget breach |
| `scripts/canary-promote.sh` | Promote canary deployment |
| `scripts/canary-rollback.sh` | Rollback canary deployment |

All scripts support environment variables for configuration. See individual script files for details.

## 🔔 Alerting

### Alert Categories

- **Application Health**: Error rates, success rates, latency
- **Resource Usage**: CPU, memory, pod status
- **Deployment Status**: Replica availability, HPA scaling
- **Canary Metrics**: Canary vs stable comparison
- **SLO Compliance**: Availability, error budget consumption
- **Error Budget**: Consumption thresholds (50%, 80%, 95%)

### Alert Channels

- Slack integration
- PagerDuty integration
- Email notifications
- GitHub notifications

## 🎯 SLO & Error Budget

### SLO Targets

- **Availability**: 99.9% (30-day rolling window)
- **Error Rate**: ≤ 0.1%
- **P95 Latency**: ≤ 500ms
- **P99 Latency**: ≤ 1000ms

### Error Budget

- **Total Budget**: 0.1% (43.2 minutes/month)
- **Warning Threshold**: 50% consumed
- **Critical Threshold**: 80% consumed
- **Emergency Threshold**: 95% consumed (auto-rollback)

### Monitoring

```bash
# Check error budget status
./scripts/check-error-budget.sh

# Generate SLO report
./scripts/generate-slo-report.sh
```

## 🚦 Environment Promotion

### Promotion Path

**Dev → Staging → Canary → Production**

### Requirements

**Dev → Staging**:
- Tests passed
- Coverage ≥ 70%
- Security: Max 5 high, 0 critical
- Approval: Not required

**Staging → Canary**:
- All tests + E2E
- Coverage ≥ 80%
- Security: Max 0 high, 0 critical
- Approval: SRE + QA

**Canary → Production**:
- All tests + Performance
- Coverage ≥ 85%
- Security: Max 0 high, 0 critical
- Canary: 10% traffic, 24h, 99% success
- Approval: SRE + Engineering Lead + Product Owner

## 🧪 Testing

### Test Types

- **Unit Tests**: Fast, isolated tests
- **Integration Tests**: Tests with service dependencies
- **E2E Tests**: End-to-end scenarios
- **Performance Tests**: Load and stress testing

### Coverage

- Minimum coverage enforced per environment
- Coverage reports uploaded as artifacts
- PR comments with coverage summary

## 🔄 Canary Deployments

### Progressive Rollout

1. **10% Traffic** (2 min observation)
2. **25% Traffic** (5 min observation)
3. **50% Traffic** (5 min observation)
4. **75% Traffic** (5 min observation)
5. **100% Traffic** (10 min validation)

### Automated Analysis

- Success rate monitoring
- Error rate tracking
- Latency comparison
- Automatic promotion/rollback

### Monitoring

```bash
# Watch canary rollout
kubectl argo rollouts get rollout canary-app -n production --watch

# Promote canary
kubectl argo rollouts promote canary-app -n production

# Rollback canary
kubectl argo rollouts undo canary-app -n production
```

## 🐛 Troubleshooting

### Common Issues

**Pipeline Failing**:
- Check GitHub Actions logs
- Verify secrets are configured
- Check test results

**Deployment Not Working**:
- Check ArgoCD application status
- Verify Kubernetes resources
- Check pod logs

**Metrics Not Showing**:
- Verify ServiceMonitor configuration
- Check Prometheus targets
- Verify metrics endpoint

For detailed troubleshooting, see [USAGE.md](./docs/USAGE.md#troubleshooting).

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run pre-commit hooks
5. Submit a pull request

## 📝 License

MIT License - see [LICENSE](./LICENSE) file for details.

## 🙏 Acknowledgments

- [ArgoCD](https://argo-cd.readthedocs.io/) - GitOps continuous delivery
- [Prometheus](https://prometheus.io/) - Metrics and monitoring
- [Grafana](https://grafana.com/) - Visualization
- [Gitleaks](https://github.com/gitleaks/gitleaks) - Secrets detection
- [TruffleHog](https://github.com/trufflesecurity/trufflehog) - Secrets scanning
- [Trivy](https://github.com/aquasecurity/trivy) - Security scanning
- [Argo Rollouts](https://argoproj.github.io/argo-rollouts/) - Advanced deployments

## 📞 Support

- **Documentation**: See [docs/](./docs/) directory
- **Issues**: Open a GitHub issue
- **Questions**: Contact the SRE team


