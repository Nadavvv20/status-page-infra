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
├── .github/workflows/          # CI/CD Deployment Pipelines
│   ├── cd-deploy.yml           # Automatically updates Helm values & triggers deployments
│   ├── gitops-sync.yml         # Monitors Drift and auto-syncs the EKS state
│   └── infra-validate.yml      # Quality gates: Terraform Validate & Helm Linting
├── helm-statuspage/            # Helm Chart for the Django Application
│   ├── templates/              # Kubernetes Resources
│   │   ├── clustersecretstore.yaml  # Connects K8s to AWS Secrets Manager
│   │   ├── externalsecret.yaml      # Syncs DB, Django, and Admin credentials
│   │   ├── grafana-github-es.yaml   # Syncs Grafana OAuth credentials
│   │   ├── hpa.yaml                 # Horizontal Pod Autoscaling rules
│   │   ├── ingress.yaml             # ALB Ingress configuration for external routing
│   │   ├── web-deployment.yaml      # Main Django web application Pods
│   │   ├── worker-deployment.yaml   # RQ worker Pods for async tasks
│   │   ├── scheduler-deployment.yaml # RQ scheduler Pods
│   │   ├── service.yaml             # Internal networking (ClusterIP)
│   │   └── serviceaccount.yaml      # K8s Service Account providing IAM role (IRSA)
│   ├── Chart.yaml              # Chart metadata and versioning
│   └── values.yaml             # Customizable values (replica counts, image tags, toggles)
├── terraform/                  # Infrastructure as Code
│   ├── environments/           # Environment-specific deployments (dev, prod)
│   └── modules/                # Reusable Terraform Modules
│       ├── cluster-addons.tf   # EKS Managed Addons (EBS CSI, VPC CNI)
│       ├── configmap.tf        # Application config map injected via Terraform
│       ├── eks.tf              # Kubernetes Cluster & Managed Node Groups
│       ├── elasticache.tf      # Managed Redis Cache
│       ├── github-actions-iam/ # Modular IAM setup for GitHub OIDC Trust
│       ├── helm_releases/      # Core K8s Addons (LB Controller, Autoscaler, Prometheus)
│       ├── iam.tf              # Cluster IAM Roles and Policies
│       ├── outputs.tf          # Module exported values
│       ├── rds.tf              # Managed PostgreSQL Database
│       ├── s3.tf               # S3 buckets for Django static assets
│       ├── secrets.tf          # AWS Secrets Manager resources and auto-generated passwords
│       ├── sg.tf               # Security Groups definition for RDS and Redis
│       ├── variables.tf        # Input variable definitions
│       └── vpc.tf              # Networking (Subnets, NAT Gateway, S3 Gateway Endpoint)
└── README.md                   # This file!
```

---

## ⚙️ CI/CD Pipeline

The project utilizes a robust and modern **GitHub Actions Pipeline** mimicking native GitOps workflows (effectively replacing older tools like Jenkins or ArgoCD).

1. **Application Build (`status-page-app` Repo)**:
   - Evaluates code linting.
   - Builds the Docker image.
   - Scans the image for vulnerabilities using **Trivy**.
   - Pushes the image to AWS ECR.
   - Triggers a `repository_dispatch` to the Infrastructure Repository.

2. **Continuous Deployment (`cd-deploy.yml`)**:
   - Captures the new Image Tag SHA.
   - Updates `helm-statuspage/values.yaml` with the newest tag and commits it back to Git (GitOps Source of Truth).
   - Executes `helm upgrade --install` against the EKS cluster.
   
3. **Continuous Reconciliation (`gitops-sync.yml`)**:
   - Runs repeatedly on a schedule.
   - Detects drift between the live cluster and the configurations defined in Git.
   - Re-syncs the cluster if unauthorized modifications are found in production.

---
### Quick Commands

**Deploy Infrastructure:**
```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply -auto-approve
```

**Deploy Helm Workloads Manually:**
```bash
helm upgrade --install statuspage ./helm-statuspage -n default
```
