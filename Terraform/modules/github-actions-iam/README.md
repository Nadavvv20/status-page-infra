# GitHub Actions IAM Module

Terraform module ליצירת IAM resources הנדרשים עבור GitHub Actions CI/CD עם AWS.

## 🎯 מה המודול עושה?

1. ✅ יוצר OIDC Provider ל-GitHub Actions
2. ✅ יוצר IAM Role עם הרשאות מינימליות (Least Privilege)
3. ✅ מגדיר הרשאות ECR (Push/Pull images)
4. ✅ מגדיר הרשאות EKS (Deploy to cluster)
5. ✅ (אופציונלי) מעדכן aws-auth ConfigMap
6. ✅ (אופציונלי) יוצר RBAC roles ב-Kubernetes

## 📦 דרישות

- Terraform >= 1.5.0
- AWS Provider >= 5.0
- Kubernetes Provider >= 2.23 (אם משתמשים ב-eks-auth.tf)
- kubectl configured (להרצת aws-auth update)

## 🚀 שימוש בסיסי

```hcl
module "github_actions_iam" {
  source = "./modules/github-actions-iam"

  # GitHub Configuration
  github_org       = "your-github-username"
  app_repo_name    = "status-page-app"
  infra_repo_name  = "status-page-infra"

  # Project
  project_name = "statuspage"

  # AWS Resources
  ecr_repository_arn = "arn:aws:ecr:us-east-1:123456789012:repository/my-app"
  eks_cluster_name   = "my-eks-cluster"
}

output "github_actions_role_arn" {
  value = module.github_actions_iam.github_actions_role_arn
}
```

## 📋 Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `github_org` | GitHub organization או username | string | ✅ Yes |
| `app_repo_name` | שם repository של האפליקציה | string | No (default: status-page-app) |
| `infra_repo_name` | שם repository של התשתית | string | No (default: status-page-infra) |
| `project_name` | שם הפרויקט למתן שמות למשאבים | string | ✅ Yes |
| `ecr_repository_arn` | ARN של ECR repository | string | ✅ Yes |
| `eks_cluster_name` | שם קלאסטר EKS | string | ✅ Yes |

## 📤 Outputs

| Name | Description |
|------|-------------|
| `github_actions_role_arn` | ARN של ה-IAM role (להעתיק ל-GitHub Secrets) |
| `github_actions_role_name` | שם ה-IAM role |
| `github_oidc_provider_arn` | ARN של OIDC provider |
| `setup_instructions` | הוראות השלמת ההגדרה |

## 🔧 שלבי ההתקנה

### שלב 1: הרצת Terraform

```bash
cd terraform/environments/dev  # או prod

terraform init
terraform plan
terraform apply

# שמור את ה-output:
terraform output github_actions_role_arn
# arn:aws:iam::123456789012:role/statuspage-github-actions-deployer
```

### שלב 2: עדכון aws-auth ConfigMap

**אופציה A: ידני (מהיר)**

```bash
kubectl edit configmap aws-auth -n kube-system

# הוסף ל-mapRoles:
- rolearn: arn:aws:iam::123456789012:role/statuspage-github-actions-deployer
  username: github-actions-deployer
  groups:
    - system:masters
```

**אופציה B: דרך Terraform (מומלץ לפרודקשן)**

```hcl
# main.tf
module "github_actions_iam" {
  source = "./modules/github-actions-iam"
  # ... existing config
}

# Add kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}

# Include the eks-auth configuration
# (uncomment the eks-auth.tf file in the module)
```

### שלב 3: הוספת Secrets ב-GitHub

**בשני ה-repositories** (app & infra):

```
GitHub → Settings → Secrets and variables → Actions → New secret

1. Secret #1:
   Name: AWS_ROLE_ARN
   Value: <paste output from terraform>

2. Secret #2:
   Name: PAT_TOKEN
   Value: <GitHub Personal Access Token>
```

### שלב 4: עדכון Workflows

```yaml
# .github/workflows/app-build.yml
# .github/workflows/cd-deploy.yml

# עדכן את:
repository: YOUR_GITHUB_USERNAME/status-page-infra
EKS_CLUSTER_NAME: your-cluster-name
```

## 🔐 אבטחה

### Trust Policy

ה-Role מוגדר עם Trust Policy מאובטח:

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:YOUR_ORG/status-page-app:*",
        "repo:YOUR_ORG/status-page-infra:*"
      ]
    }
  }
}
```

**זה אומר:**
- ✅ רק workflows מ-repositories ספציפיים יכולים להשתמש ב-Role
- ✅ אף משתמש לא יכול להשתמש ב-Role ישירות
- ✅ אין Access Keys שיכולים לדלוף

### Least Privilege

ה-Role מקבל רק ההרשאות הנדרשות:
- ECR: Push/Pull images לרפוזיטורי ספציפי
- EKS: DescribeCluster בלבד (הגישה לפודים דרך aws-auth)
- אין גישה ל-S3, RDS, או שירותים אחרים

### RBAC (אופציונלי)

במקום `system:masters`, אפשר להשתמש ב-RBAC מותאם אישית:

```bash
# Uncomment the RBAC section in eks-auth.tf
# זה יוצר ClusterRole עם הרשאות ספציפיות בלבד
```

## 🧪 בדיקה

```bash
# בדוק שה-OIDC Provider נוצר
aws iam list-open-id-connect-providers

# בדוק שה-Role נוצר
aws iam get-role --role-name statuspage-github-actions-deployer

# בדוק את ה-policies
aws iam list-attached-role-policies --role-name statuspage-github-actions-deployer

# בדוק aws-auth
kubectl get configmap aws-auth -n kube-system -o yaml
```

## 🔄 עדכון המודול

```bash
# אם שינית משהו במודול:
terraform plan
terraform apply

# אם שינית repos או permissions:
# עדכן את התשתית מחדש
```

## 🗑️ הסרה

```bash
terraform destroy

# Note: ה-OIDC Provider יוסר גם כן
# אם יש לך workflows אחרים שמשתמשים בו, שמור אותו
```

## 📚 קישורים שימושיים

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [EKS aws-auth ConfigMap](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)

## 🆘 Troubleshooting

### Error: "User is not authorized"

```bash
# בדוק שה-Trust Policy נכון:
aws iam get-role --role-name statuspage-github-actions-deployer \
  --query 'Role.AssumeRolePolicyDocument'

# ודא שיש:
# - Federated: oidc-provider/token.actions.githubusercontent.com
# - Condition עם repo names
```

### Error: "Access denied in Kubernetes"

```bash
# בדוק aws-auth:
kubectl get configmap aws-auth -n kube-system -o yaml | grep github

# אם לא מופיע, הוסף ידנית:
kubectl edit configmap aws-auth -n kube-system
```

### Error: "OIDC provider already exists"

```bash
# אם ה-provider כבר קיים:
# 1. Import to Terraform:
terraform import aws_iam_openid_connect_provider.github_actions \
  arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

# 2. או הסר את ה-resource מה-Terraform ותשתמש ב-data source:
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}
```

## 🎓 מושגים

- **OIDC** - OpenID Connect, פרוטוקול אימות המאפשר ל-GitHub Actions להתחבר ל-AWS בלי secrets
- **IAM Role** - תפקיד זמני ב-AWS עם הרשאות ספציפיות
- **Trust Policy** - מגדיר מי יכול "ללבוש" את ה-Role
- **aws-auth** - ConfigMap ב-Kubernetes שמפה בין IAM roles ל-RBAC users
- **Least Privilege** - עקרון אבטחה - תן רק את ההרשאות המינימליות הנדרשות

---

**נוצר עבור**: StatusPage CI/CD Pipeline  
**גרסה**: 1.0.0  
**תאריך**: March 2026
