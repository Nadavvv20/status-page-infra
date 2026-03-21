# 🚀 Staging & Production Deployment Guide

## Overview

This guide covers the complete staging → production deployment pipeline for the Status Page application.

---

## Pipeline Flow

```
status-page-app → CI/CD Build → ECR Push → repository_dispatch
    ↓
status-page-infra → Staging Deploy (automatic) → Tests → Report
    ↓
[Manual Review] → Production Deploy (manual YES) → Health Checks
```

---

## Staging Deployment

### Automatic Trigger (Normal Flow)

The staging deployment is triggered automatically when:
1. `status-page-app` CI/CD builds a new Docker image
2. The image is pushed to ECR
3. A `repository_dispatch` event (`update-image`) is sent to `status-page-infra`

**No manual action required** — the staging pipeline runs all 12 stages automatically.

### Manual Trigger

To manually deploy to staging:

1. Go to **Actions** → **CD - Deploy to Staging (Complete)**
2. Click **Run workflow**
3. Optionally enter a custom image tag
4. Click **Run workflow**

### Staging Test Stages

| Stage | What It Tests | Blocking? |
|-------|--------------|-----------|
| 1. Prepare | Extracts image tag and metadata | Yes |
| 2. Validate Source | Verifies trigger is from status-page-app | Yes |
| 3. Validate Infrastructure | Terraform init/validate | Yes |
| 4. Validate Helm | Lint, template, secrets scan | Yes |
| 5. Deploy | Helm upgrade --install to staging namespace | Yes |
| 6. Pod Health | Rollout status, pod state, health endpoint | Yes |
| 7. Database | Connection, migrations, tables | Yes |
| 8. Configuration | Env vars, secrets, ConfigMap | Yes |
| 9. Redis | Connection, cache operations | No (optional) |
| 10. S3 | Connection, bucket access | No (optional) |
| 11. API Endpoints | /, /api/status/, /admin/ | Yes |
| 12. Summary | Report, notify status-page-app | Always runs |

### Checking Staging Status

```bash
# View staging pods
kubectl get pods -n staging -o wide

# View staging services
kubectl get svc -n staging

# View staging ingress
kubectl get ingress -n staging

# View Helm release
helm list -n staging

# View pod logs
kubectl logs -n staging -l app=statuspage-staging-web -c web --tail=100

# Describe a pod
kubectl describe pod -n staging <pod-name>
```

---

## Production Deployment

### Prerequisites

Before deploying to production:
1. ✅ Staging deployment completed successfully
2. ✅ All test stages passed (review the staging summary report)
3. ✅ Manual verification of staging environment (optional but recommended)

### How to Deploy to Production

1. Go to **Actions** → **CD - Deploy to Production**
2. Click **Run workflow**
3. **Approval**: Type exactly `YES` (case-sensitive)
4. **Source**: Select `staging-verified` (recommended) or `custom-image-tag`
5. **Image tag**: Leave empty for staging-verified, or enter custom tag
6. Click **Run workflow**

### Production Checks

```bash
# View production pods
kubectl get pods -n statuspage -o wide

# View production services
kubectl get svc -n statuspage

# View production ingress
kubectl get ingress -n statuspage

# View Helm release
helm list -n statuspage

# View HPA status
kubectl get hpa -n statuspage
```

---

## Secrets Management

### Required GitHub Repository Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `PAT_TOKEN` | GitHub Personal Access Token (for cross-repo dispatch) |

### Kubernetes Secrets (Managed by External Secrets Operator)

| Secret | Namespace | Source |
|--------|-----------|--------|
| `statuspage-secrets` | statuspage / staging | AWS Secrets Manager |
| `statuspage-github-secret` | statuspage / staging | AWS Secrets Manager |

Secrets are automatically synced from AWS Secrets Manager by the External Secrets Operator. The `ClusterSecretStore` and `ExternalSecret` resources in the Helm chart handle this.

---

## Environment Differences

| Setting | Staging | Production |
|---------|---------|------------|
| Namespace | `staging` | `statuspage` |
| Helm Release | `statuspage-staging` | `statuspage` |
| Values File | `values-staging.yaml` | `values-production.yaml` |
| Web Replicas | 1 | 3 |
| Worker Replicas | 1 | 2 |
| CPU Limit | 250m | 1000m |
| Memory Limit | 512Mi | 2Gi |
| Autoscaling | Disabled | Enabled (3-10 replicas) |
| Debug | False | False |
| SSL/TLS | No | Yes (ACM Certificate) |
| Ingress Group | statuspage-staging-group | statuspage-group |
| Deployment | Automatic | Manual (requires YES) |

---

## Troubleshooting

### Staging deployment not triggered

1. Check that `status-page-app` CI/CD completed successfully
2. Verify the `repository_dispatch` event was sent:
   - Check the app repo's workflow logs for the dispatch step
3. Verify `PAT_TOKEN` secret is set and has `repo` scope
4. Check the infra repo's Actions tab for the staging workflow

### Staging pods in CrashLoopBackOff

```bash
# Check pod events
kubectl describe pod -n staging <pod-name>

# Check pod logs
kubectl logs -n staging <pod-name> -c web --previous

# Check init container logs
kubectl logs -n staging <pod-name> -c init-db
```

Common causes:
- Database not reachable (check RDS security groups)
- Secrets not synced (check ExternalSecret status)
- Image not found in ECR

### Staging tests failing

1. **Pod Health (Stage 6)**: Check rollout status, pod events, init containers
2. **Database (Stage 7)**: Verify RDS endpoint, security groups, credentials
3. **Configuration (Stage 8)**: Check ConfigMap exists in staging namespace
4. **Redis (Stage 9)**: Verify ElastiCache endpoint, security groups
5. **API (Stage 11)**: Check application logs for errors

### Production approval rejected

The approval input must be exactly `YES` (uppercase). Any other value will be rejected.

### Image not found in ECR

```bash
# List images in ECR
aws ecr describe-images --repository-name nadav-statuspage --region us-east-1

# Check specific tag
aws ecr describe-images --repository-name nadav-statuspage \
  --image-ids imageTag=<TAG> --region us-east-1
```

### ExternalSecrets not syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n staging
kubectl describe externalsecret -n staging django-secret-sync

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore aws-secretsmanager
```

---

## Manual Helm Commands

### Deploy to staging
```bash
helm upgrade --install statuspage-staging ./helm-statuspage \
  --namespace staging \
  --values helm-statuspage/values.yaml \
  --values helm-statuspage/values-staging.yaml \
  --set image.tag=<IMAGE_TAG> \
  --wait --timeout 10m --atomic
```

### Deploy to production
```bash
helm upgrade --install statuspage ./helm-statuspage \
  --namespace statuspage \
  --values helm-statuspage/values.yaml \
  --values helm-statuspage/values-production.yaml \
  --set image.tag=<IMAGE_TAG> \
  --wait --timeout 10m --atomic
```

### Rollback staging
```bash
helm rollback statuspage-staging -n staging
```

### Rollback production
```bash
helm rollback statuspage -n statuspage
```

### Uninstall staging
```bash
helm uninstall statuspage-staging -n staging
```
