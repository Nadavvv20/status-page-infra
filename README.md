# Status Page Infrastructure 🚀

This repository contains the Infrastructure as Code (IaC) and deployment configurations for the Status Page project. It leverages modern DevOps practices, including Terraform, Helm, and GitHub Actions, to provision a highly available, scalable, and secure environment on AWS.

---

## 🏗️ Architecture Overview

The infrastructure robustly supports the **Django Status Page Web Application**, ensuring performance and reliability. 

### Core Components:
- **AWS EKS (Elastic Kubernetes Service)**: Manages the containerized application workloads across multiple Availability Zones (AZs).
- **Amazon RDS (Postgres 15)**: A managed relational database used as the primary data store.
- **Amazon ElastiCache (Redis 7)**: Provides fast in-memory caching and message queuing for background tasks.
- **Amazon ECR**: A highly available image registry for storing the application Docker images.
- **ALB (Application Load Balancer)**: Provisions automatically via the AWS Load Balancer Controller to route external traffic to the EKS cluster.
- **VPC & Networking**: A custom VPC configured with Public, Private, and Database subnets to ensure strict network isolation.

---

## 📈 Key Perspectives

### High Availability (HA)
- **Multi-AZ Deployments**: EKS nodes, RDS, and ElastiCache are dispersed across 3 Availability Zones (`us-east-1a`, `us-east-1b`, `us-east-1c`) to survive datacenter-level failures.
- **RDS Multi-AZ**: Enabled to automatically failover to a standby DB replica in case of a disruption.
- **Redis Failover**: Configured with automatic failover and 2 cache clusters.
- **Kubernetes Features**: Pod anti-affinity and ReplicaSets ensure the application remains strictly available across scheduled or unscheduled node downtime.

### Scalability
- **Horizontal Pod Autoscaler (HPA)**: The Helm chart automatically scales Django application pods (`minReplicas: 2`, `maxReplicas: 5`) based on CPU and memory utilization metrics.
- **Cluster Autoscaler**: Deployed to the EKS cluster to automatically provision or downscale EC2 worker nodes (`min_size: 1`, `max_size: 2`) when pod resource demands fluctuate.
- **Managed Database & Cache**: RDS and ElastiCache instance types and storage can be dynamically upscaled with minimal downtime as data requirements grow.

### Security
- **OIDC Authentication**: GitHub Actions authenticate securely with AWS using OpenID Connect (OIDC), completely eliminating risks associated with static long-lived Access Keys.
- **Least Privilege IAM (IRSA)**: IAM Roles for Service Accounts (IRSA) restrict the capabilities of individual Kubernetes Pods to only the AWS resources they absolutely need (e.g., `external-secrets`, `aws-load-balancer-controller`).
- **External Secrets Operator**: Kubernetes secrets are never committed to code. They are fetched dynamically from AWS Secrets Manager and injected directly into the cluster securely.
- **Network Isolation**: The application and databases reside in Private and Database subnets. Only the public-facing ALB is accessible from the internet.

### Observability
- **Kube-Prometheus-Stack**: A fully integrated monitoring suite for capturing EKS workloads, node metrics, and application performance.
- **Grafana with GitHub OAuth**: Metric dashboards secured via SSO. 
- **Loki Stack**: Aggregates container logs for rapid troubleshooting and auditing.

---

## 🗂️ File & Directory Structure

```text
status-page-infra/
├── .github/workflows/                    # CI/CD Deployment Pipelines
│   ├── cd-deploy.yml                     # Legacy: direct deploy to EKS
│   ├── cd-deploy-staging-complete.yml    # ⭐ Staging pipeline (12 stages, auto-triggered)
│   ├── cd-deploy-production.yml          # ⭐ Production pipeline (manual approval)
│   ├── gitops-sync.yml                   # Monitors drift and auto-syncs EKS state
│   ├── infra-validate.yml                # Quality gates: Terraform & Helm validation
│   └── tests-and-audit.yml              # CI/CD tests & security audit
├── helm-statuspage/                      # Helm Chart for the Django Application
│   ├── templates/                        # Kubernetes Resources
│   │   ├── clustersecretstore.yaml       # Connects K8s to AWS Secrets Manager
│   │   ├── externalsecret.yaml           # Syncs DB, Django, and Admin credentials
│   │   ├── github-externalsecret.yaml    # Syncs GitHub OAuth credentials
│   │   ├── grafana-github-es.yaml        # Syncs Grafana OAuth credentials
│   │   ├── hpa.yaml                      # Horizontal Pod Autoscaling rules
│   │   ├── ingress.yaml                  # ALB Ingress configuration
│   │   ├── web-deployment.yaml           # Main Django web application Pods
│   │   ├── worker-deployment.yaml        # RQ worker Pods for async tasks
│   │   ├── scheduler-deployment.yaml     # RQ scheduler Pods
│   │   ├── service.yaml                  # Internal networking (ClusterIP)
│   │   └── serviceaccount.yaml           # K8s Service Account (IRSA)
│   ├── Chart.yaml                        # Chart metadata and versioning
│   ├── values.yaml                       # Base values (shared across environments)
│   ├── values-staging.yaml               # ⭐ Staging overrides (1 replica, lower resources)
│   └── values-production.yaml            # ⭐ Production overrides (3 replicas, HPA, SSL)
├── Terraform/                            # Infrastructure as Code
│   ├── environments/                     # Environment-specific deployments
│   │   ├── dev/                          # Development environment
│   │   └── prod/                         # Production environment
│   └── modules/                          # Reusable Terraform Modules
│       ├── cluster-addons.tf             # EKS Managed Addons (EBS CSI, VPC CNI)
│       ├── configmap.tf                  # Production ConfigMap (statuspage namespace)
│       ├── staging.tf                    # ⭐ Staging namespace & ConfigMap
│       ├── eks.tf                        # Kubernetes Cluster & Managed Node Groups
│       ├── elasticache.tf                # Managed Redis Cache
│       ├── github-actions-iam/           # Modular IAM for GitHub OIDC Trust
│       ├── helm_releases/                # Core K8s Addons (LB Controller, Prometheus)
│       ├── iam.tf                        # Cluster IAM Roles and Policies
│       ├── outputs.tf                    # Module exported values
│       ├── rds.tf                        # Managed PostgreSQL Database
│       ├── s3.tf                         # S3 buckets for static assets
│       ├── secrets.tf                    # AWS Secrets Manager resources
│       ├── sg.tf                         # Security Groups (RDS, Redis)
│       ├── storage.tf                    # EFS storage for Grafana
│       ├── variables.tf                  # Input variable definitions
│       └── vpc.tf                        # VPC, Subnets, NAT Gateway
├── scripts/                              # Utility scripts
├── tests/                                # CI/CD tests
├── docs/                                 # Documentation
└── README.md                             # This file!
```

---

## ⚙️ CI/CD Pipeline

The project utilizes a robust and modern **GitHub Actions Pipeline** with a full staging → production promotion workflow.

### Pipeline Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                   status-page-app (main)                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  app-build.yml                                         │ │
│  │  1. Lint & Test code                                   │ │
│  │  2. Build Docker image                                 │ │
│  │  3. Scan with Trivy                                    │ │
│  │  4. Push to ECR                                        │ │
│  │  5. repository_dispatch: update-image ──────────────┐  │ │
│  └─────────────────────────────────────────────────────│──┘ │
└────────────────────────────────────────────────────────│────┘
                                                         │
                                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  status-page-infra                           │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  cd-deploy-staging-complete.yml (AUTOMATIC)           │  │
│  │                                                       │  │
│  │  Stage 1:  Prepare (extract image tag & metadata)     │  │
│  │  Stage 2:  Validate Source & Security                 │  │
│  │  Stage 3:  Validate Infrastructure (Terraform)        │  │
│  │  Stage 4:  Validate Helm Charts (lint & template)     │  │
│  │  Stage 5:  Deploy to Staging Namespace                │  │
│  │  Stage 6:  Test Pod Health                            │  │
│  │  Stage 7:  Test Database (connectivity & migrations)  │  │
│  │  Stage 8:  Test Configuration (env vars & secrets)    │  │
│  │  Stage 9:  Test Redis (connection & cache ops)        │  │
│  │  Stage 10: Test S3 (connection)                       │  │
│  │  Stage 11: Test API Endpoints (/, /api/, /admin/)     │  │
│  │  Stage 12: Summary Report & Notify                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                  │
│                          ▼                                  │
│                  [Manual Review]                             │
│                          │                                  │
│                          ▼                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  cd-deploy-production.yml (MANUAL - requires YES)     │  │
│  │                                                       │  │
│  │  Job 1: Verify Approval (must type "YES")             │  │
│  │  Job 2: Deploy to Production Namespace                │  │
│  │  Job 3: Production Report & Notify                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Workflow Details

1. **Application Build (`status-page-app` repo)**:
   - Evaluates code linting
   - Builds the Docker image
   - Scans the image for vulnerabilities using **Trivy**
   - Pushes the image to AWS ECR
   - Triggers a `repository_dispatch` (`update-image`) to the Infrastructure Repository

2. **Staging Deployment (`cd-deploy-staging-complete.yml`)** — *Automatic*:
   - Triggered by `repository_dispatch` from status-page-app
   - Validates source, infrastructure, and Helm charts
   - Deploys to `staging` namespace with reduced resources (1 replica, 512Mi)
   - Runs 6 comprehensive test stages (pod health, DB, config, Redis, S3, API)
   - Generates detailed summary report with pass/fail for each stage
   - Notifies status-page-app with results

3. **Production Deployment (`cd-deploy-production.yml`)** — *Manual*:
   - Requires explicit `YES` approval via workflow_dispatch
   - Resolves image tag from staging or custom input
   - Verifies image exists in ECR
   - Deploys to `statuspage` namespace with production resources (3 replicas, HPA, SSL)
   - Runs health checks and verifies all replicas
   - Notifies status-page-app with deployment status

4. **Continuous Reconciliation (`gitops-sync.yml`)**:
   - Runs on schedule and push events
   - Detects drift between live cluster and Git state
   - Re-syncs the cluster if modifications are found

### Environment Comparison

| Setting | Staging | Production |
|---------|---------|------------|
| Namespace | `staging` | `statuspage` |
| Web Replicas | 1 | 3 |
| Worker Replicas | 1 | 2 |
| CPU Limit | 250m | 1000m |
| Memory Limit | 512Mi | 2Gi |
| Autoscaling | Disabled | Enabled (3-10) |
| Debug | False | False |
| SSL/TLS | No | Yes (ACM) |
| Trigger | Automatic | Manual (YES) |

---
### Quick Commands

**Deploy Infrastructure:**
```bash
cd Terraform/environments/dev
terraform init
terraform plan
terraform apply -auto-approve
```

**Deploy to Staging Manually:**
```bash
helm upgrade --install statuspage-staging ./helm-statuspage \
  --namespace staging \
  --values helm-statuspage/values.yaml \
  --values helm-statuspage/values-staging.yaml \
  --set image.tag=<IMAGE_TAG>
```

**Deploy to Production Manually:**
```bash
helm upgrade --install statuspage ./helm-statuspage \
  --namespace statuspage \
  --values helm-statuspage/values.yaml \
  --values helm-statuspage/values-production.yaml \
  --set image.tag=<IMAGE_TAG>
```

**Check Staging Status:**
```bash
kubectl get pods -n staging
kubectl get ingress -n staging
helm list -n staging
```

**Check Production Status:**
```bash
kubectl get pods -n statuspage
kubectl get ingress -n statuspage
helm list -n statuspage
```
