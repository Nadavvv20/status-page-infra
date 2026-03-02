# ⚡ Quick Start - GitHub Actions CI/CD

מדריך מהיר להפעלת CI/CD pipeline עם GitHub Actions במקום Jenkins ו-ArgoCD.

## 🎯 מה נבנה?

```
┌─────────────────────────────────────────────────────────────┐
│                    CI/CD Flow                                │
└─────────────────────────────────────────────────────────────┘

📝 Code Push to GitHub
    ↓
🔨 GitHub Actions: Build → Test → Scan
    ↓
📦 Push to Amazon ECR
    ↓
🔔 Trigger Infrastructure Repo
    ↓
📝 Update values.yaml (GitOps)
    ↓
🚀 Deploy to EKS with Helm
    ↓
🔄 GitOps Sync (every 5 min)
    ↓
✅ Live Application!
```

---

## 📁 מה נוצר בפרויקט?

### **Repo: status-page-app**
```
.github/workflows/
└── app-build.yml ✅          # CI Pipeline (Jenkins replacement)
```

### **Repo: status-page-infra**
```
.github/workflows/
├── cd-deploy.yml ✅          # CD Pipeline
├── gitops-sync.yml ✅        # GitOps Auto-Sync (ArgoCD replacement)
└── infra-validate.yml ✅     # Existing

Terraform/modules/
└── github-actions-iam/       # IAM Module for OIDC
    ├── main.tf ✅
    ├── eks-auth.tf ✅
    ├── example.tf ✅
    └── README.md ✅

├── CI-CD-GUIDE.md ✅         # מדריך מלא של CI/CD
├── SETUP-GUIDE.md ✅         # הוראות הגדרה צעד אחר צעד
└── QUICKSTART.md ✅          # המסמך הזה
```

---

## ⚡ התחלה מהירה (15 דקות)

### 1️⃣ הגדרת IAM ב-AWS (5 דקות)

```bash
cd status-page-infra/Terraform/environments/dev

# ערוך את הקובץ main.tf והוסף:
```

```hcl
module "github_actions_iam" {
  source = "../../modules/github-actions-iam"

  github_org       = "YOUR_GITHUB_USERNAME"  # 🔴 שנה!
  app_repo_name    = "status-page-app"
  infra_repo_name  = "status-page-infra"
  project_name     = "statuspage"

  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = module.eks.cluster_name
}

output "github_role_arn" {
  value = module.github_actions_iam.github_actions_role_arn
}
```

```bash
# הרץ Terraform
terraform init
terraform plan
terraform apply

# 📋 שמור את ה-output:
# github_role_arn = arn:aws:iam::123456789012:role/...
```

### 2️⃣ עדכון aws-auth ConfigMap (2 דקות)

```bash
kubectl edit configmap aws-auth -n kube-system

# הוסף בסוף mapRoles:
- rolearn: arn:aws:iam::123456789012:role/statuspage-github-actions-deployer
  username: github-actions-deployer
  groups:
    - system:masters
```

שמור וצא (`:wq` ב-vim).

### 3️⃣ יצירת GitHub PAT (3 דקות)

1. לך ל: https://github.com/settings/tokens/new
2. Token name: `CI/CD Pipeline`
3. Expiration: `90 days`
4. ✅ Select scopes:
   - ✅ `repo` (Full control)
   - ✅ `workflow` (Update workflows)
5. Generate token
6. 📋 **העתק את ה-token!** (לא תראה אותו שוב)

### 4️⃣ הוספת Secrets ל-GitHub (5 דקות)

**ב-Repo: status-page-app**
```
Settings → Secrets and variables → Actions → New repository secret

Secret 1:
- Name: AWS_ROLE_ARN
- Value: arn:aws:iam::123456789012:role/statuspage-github-actions-deployer

Secret 2:
- Name: PAT_TOKEN
- Value: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**ב-Repo: status-page-infra**
```
(אותם secrets בדיוק)

Secret 1: AWS_ROLE_ARN
Secret 2: PAT_TOKEN
```

### 5️⃣ עדכון Workflows

**ערוך**: `status-page-app/.github/workflows/app-build.yml`

```yaml
# שורה 72 - עדכן שם repository:
repository: YOUR_GITHUB_USERNAME/status-page-infra
```

**ערוך**: `status-page-infra/.github/workflows/cd-deploy.yml`

```yaml
# שורה 19 - עדכן שם קלאסטר:
EKS_CLUSTER_NAME: your-cluster-name
```

**ערוך**: `status-page-infra/.github/workflows/gitops-sync.yml`

```yaml
# שורה 18 - עדכן שם קלאסטר:
EKS_CLUSTER_NAME: your-cluster-name
```

---

## 🚀 בדיקה ראשונה

### Push קוד ל-App Repo:

```bash
cd status-page-app
git add .
git commit -m "feat: enable CI/CD pipeline"
git push origin main
```

### צפה ב-Pipeline:

```
GitHub → status-page-app → Actions → "CI - Build, Scan & Push to ECR"
```

**צריך לראות:**
- ✅ Linting
- ✅ Build Docker image
- ✅ Trivy security scan
- ✅ Push to ECR
- ✅ Trigger infra update

### בדוק CD Deployment:

```
GitHub → status-page-infra → Actions → "CD - Deploy to EKS"
```

**צריך לראות:**
- ✅ Update values.yaml
- ✅ Commit to Git
- ✅ Deploy with Helm
- ✅ Verify pods

### בדוק שהאפליקציה עלתה:

```bash
kubectl get pods -n default -l app.kubernetes.io/name=statuspage
kubectl get ingress -n default

# קבל את ה-ALB URL:
kubectl get ingress -n default -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# פתח בדפדפן:
# http://<alb-url>
```

---

## ✅ Checklist הצלחה

- [ ] IAM OIDC Provider נוצר ב-AWS
- [ ] IAM Role נוצר עם הרשאות ECR + EKS
- [ ] Role נוסף ל-aws-auth ConfigMap
- [ ] GitHub PAT נוצר
- [ ] Secrets נוספו לשני ה-repos
- [ ] Repository names עודכנו ב-workflows
- [ ] Cluster name עודכן ב-workflows
- [ ] CI Pipeline רץ והצליח
- [ ] CD Pipeline רץ והצליח
- [ ] Pods עולים ב-EKS
- [ ] Application נגישה דרך ALB

---

## 🎓 מה הלאה?

### קרא את המדרכים המלאים:

1. **[CI-CD-GUIDE.md](CI-CD-GUIDE.md)** - הסבר מפורט על כל workflow
2. **[SETUP-GUIDE.md](SETUP-GUIDE.md)** - הגדרות מתקדמות ו-troubleshooting
3. **[Terraform Module README](Terraform/modules/github-actions-iam/README.md)** - תיעוד מלא של IAM module

### שיפורים אפשריים:

- 🔐 **הוסף Secrets Manager** במקום Kubernetes Secrets
- 🧪 **הוסף Tests** ל-CI Pipeline (pytest, integration tests)
- 📊 **Monitoring** - הוסף Prometheus metrics ל-GitHub Actions
- 🌍 **Multi-Environment** - הפרד dev/staging/prod
- 🔄 **Rollback** - הוסף workflow לחזרה לגרסה קודמת
- 📝 **Notifications** - שלח התראות ל-Slack/Email

---

## 🆘 נתקעת?

### בעיות נפוצות:

**Pipeline נכשל בשלב AWS credentials:**
```bash
# בדוק ש-AWS_ROLE_ARN נכון:
aws iam get-role --role-name statuspage-github-actions-deployer

# בדוק את Trust Policy:
aws iam get-role --role-name statuspage-github-actions-deployer \
  --query 'Role.AssumeRolePolicyDocument'
```

**אין גישה ל-Kubernetes:**
```bash
# בדוק aws-auth:
kubectl get configmap aws-auth -n kube-system -o yaml | grep github
```

**Helm deployment נכשל:**
```bash
# בדוק pods:
kubectl get pods -n default
kubectl describe pod <pod-name> -n default

# בדוק events:
kubectl get events -n default --sort-by='.lastTimestamp'
```

### קבל עזרה:

- 📖 קרא [SETUP-GUIDE.md](SETUP-GUIDE.md) - Troubleshooting מפורט
- 🔍 בדוק logs ב-GitHub Actions
- 🐛 בדוק errors ב-kubectl

---

## 📊 השוואה: GitHub Actions vs Jenkins/ArgoCD

| תכונה | GitHub Actions | Jenkins + ArgoCD |
|--------|---------------|------------------|
| **תחזוקה** | ✅ אפס | ❌ שרתים נוספים |
| **עלות** | ✅ חינם/נמוכה | ❌ EC2 instances |
| **Setup** | ✅ 15 דקות | ❌ שעות |
| **GitOps** | ✅ כן | ✅ כן |
| **UI** | ⚠️ בסיסי | ✅ מתקדם |
| **אבטחה** | ✅ OIDC | ⚠️ Access Keys |
| **סקיילינג** | ✅ אוטומטי | ❌ ידני |

**המלצה:** התחל עם GitHub Actions. פשוט, יעיל, ומאובטח.

---

## 🎉 סיכום

**הצלחת ליצור CI/CD מלא עם:**
- ✅ Build & Test automation
- ✅ Security scanning
- ✅ ECR image management
- ✅ GitOps deployment
- ✅ Auto-sync with drift detection
- ✅ Zero maintenance (no Jenkins/ArgoCD servers)

**זרימה מלאה:**
```
git push → CI → ECR → CD → EKS → GitOps Sync → Live! 🚀
```

**ללא שרתים נוספים, ללא תחזוקה, ללא access keys.**

---

**Created by:** GitHub Actions CI/CD Team  
**Date:** March 2026  
**Version:** 1.0.0
