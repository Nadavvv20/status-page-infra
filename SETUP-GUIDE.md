# CI/CD Setup Guide - הגדרות שלב אחר שלב

## 📋 דברים שצריך להגדיר לפני שהכל עובד

---

## 1️⃣ הגדרת AWS OIDC Provider (חובה!)

### למה צריך את זה?
במקום להשתמש ב-Access Keys (שזה סיכון אבטחתי), GitHub Actions משתמש ב-OIDC להתחברות זמנית ל-AWS.

### יצירת OIDC Provider (פעם אחת בחשבון):

```bash
# Option A: דרך AWS Console
# ------------------------------
# 1. IAM → Identity providers → Add provider
# 2. Provider type: OpenID Connect
# 3. Provider URL: https://token.actions.githubusercontent.com
# 4. Audience: sts.amazonaws.com
# 5. Click "Add provider"


# Option B: דרך Terraform
# ------------------------------
# הוסף לקובץ Terraform שלך:
```

```hcl
# terraform/modules/iam/github-oidc.tf
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = [
    "sts.amazonaws.com"
  ]
  
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
  
  tags = {
    Name = "GitHub Actions OIDC Provider"
  }
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}
```

---

## 2️⃣ יצירת IAM Role ל-GitHub Actions

### הרשאות שה-Role צריך:
- ✅ ECR: Push images
- ✅ EKS: Update kubeconfig, deploy
- ✅ S3: (אם תרצה בעתיד לקבצים סטטיים)

```hcl
# terraform/modules/iam/github-actions-role.tf

# 1. Trust Policy - מי יכול לקחת את ה-Role
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:YOUR_GITHUB_USERNAME/status-page-app:*",
        "repo:YOUR_GITHUB_USERNAME/status-page-infra:*"
      ]
    }
  }
}

# 2. יצירת ה-Role
resource "aws_iam_role" "github_actions_deployer" {
  name               = "github-actions-eks-deployer"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  
  tags = {
    Name = "GitHub Actions EKS Deployer"
  }
}

# 3. הרשאות ECR - Push/Pull images
data "aws_iam_policy_document" "ecr_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecr_permissions" {
  name   = "github-actions-ecr-access"
  policy = data.aws_iam_policy_document.ecr_permissions.json
}

resource "aws_iam_role_policy_attachment" "ecr_permissions" {
  role       = aws_iam_role.github_actions_deployer.name
  policy_arn = aws_iam_policy.ecr_permissions.arn
}

# 4. הרשאות EKS - Deploy to cluster
data "aws_iam_policy_document" "eks_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_permissions" {
  name   = "github-actions-eks-access"
  policy = data.aws_iam_policy_document.eks_permissions.json
}

resource "aws_iam_role_policy_attachment" "eks_permissions" {
  role       = aws_iam_role.github_actions_deployer.name
  policy_arn = aws_iam_policy.eks_permissions.arn
}

# 5. Output - תצטרך את זה ל-GitHub Secrets
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deployer.arn
  description = "Copy this ARN to GitHub Secrets as AWS_ROLE_ARN"
}
```

### הרצת Terraform:
```bash
cd terraform
terraform init
terraform plan
terraform apply

# שמור את ה-ARN שיוצא:
# github_actions_role_arn = arn:aws:iam::992382545251:role/github-actions-eks-deployer
```

---

## 3️⃣ עדכון EKS aws-auth ConfigMap

### למה?
GitHub Actions צריך הרשאות ב-Kubernetes עצמו, לא רק ב-AWS.

### הוספת ה-Role ל-ConfigMap:

```bash
# Option A: דרך kubectl
kubectl edit configmap aws-auth -n kube-system

# הוסף לסקשן mapRoles:
mapRoles: |
  - rolearn: arn:aws:iam::992382545251:role/github-actions-eks-deployer
    username: github-actions-deployer
    groups:
      - system:masters
```

```yaml
# Option B: דרך Terraform
# terraform/modules/eks/aws-auth.tf

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  
  data = {
    mapRoles = yamlencode(concat(
      # Existing node roles
      [
        {
          rolearn  = aws_iam_role.eks_node_group_role.arn
          username = "system:node:{{EC2PrivateDNSName}}"
          groups   = ["system:bootstrappers", "system:nodes"]
        }
      ],
      # GitHub Actions role
      [
        {
          rolearn  = aws_iam_role.github_actions_deployer.arn
          username = "github-actions-deployer"
          groups   = ["system:masters"]  # Full admin - in production, use RBAC
        }
      ]
    ))
  }
  
  force = true
}
```

⚠️ **בפרודקשן אמיתי**: אל תתן `system:masters`, תשתמש ב-RBAC עם ServiceAccount ספציפי.

---

## 4️⃣ יצירת GitHub Personal Access Token (PAT)

### למה צריך?
כדי ש-app repo יוכל לשלוח events ל-infra repo, וכדי ש-workflows יוכלו לעשות commit.

### צעדים:

1. **לך ל-GitHub Settings**:
   ```
   GitHub.com → Your Profile Picture → Settings
   ```

2. **Developer settings**:
   ```
   Scroll down → Developer settings → Personal access tokens → Tokens (classic)
   ```

3. **Generate new token**:
   ```
   Click "Generate new token (classic)"
   
   Token name: GitHub Actions CI/CD
   
   Expiration: 90 days (או No expiration אם לא איכפת לך)
   
   ✅ Select scopes:
      ✅ repo (Full control of private repositories)
         ✅ repo:status
         ✅ repo_deployment
         ✅ public_repo
      ✅ workflow (Update GitHub Action workflows)
   
   Click "Generate token"
   ```

4. **שמור את ה-Token**:
   ```
   תקבל משהו כמו: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   
   ⚠️ שמור אותו! לא תראה אותו שוב!
   ```

---

## 5️⃣ הגדרת GitHub Secrets

### ב-Repo: `status-page-app`

```
Repository → Settings → Secrets and variables → Actions → New repository secret
```

**Secrets להוסיף:**

1. **AWS_ROLE_ARN**
   ```
   Name: AWS_ROLE_ARN
   Value: arn:aws:iam::992382545251:role/github-actions-eks-deployer
   ```

2. **PAT_TOKEN**
   ```
   Name: PAT_TOKEN
   Value: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

### ב-Repo: `status-page-infra`

**אותם Secrets:**

1. **AWS_ROLE_ARN**
   ```
   Name: AWS_ROLE_ARN
   Value: arn:aws:iam::992382545251:role/github-actions-eks-deployer
   ```

2. **PAT_TOKEN**
   ```
   Name: PAT_TOKEN
   Value: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

---

## 6️⃣ עדכון שמות ב-Workflows

### קבצים לערוך:

#### 1. `status-page-app/.github/workflows/app-build.yml`

```yaml
# ליין 72 - עדכן את שם הארגון/משתמש שלך
repository: YOUR_GITHUB_USERNAME/status-page-infra
```

**להחליף:**
```yaml
repository: nadavbh/status-page-infra  # דוגמה
```

#### 2. `status-page-infra/.github/workflows/cd-deploy.yml`

```yaml
# ליין 10 - עדכן שם קלאסטר (אם שונה)
EKS_CLUSTER_NAME: Nadav-Statuspage-Project-DEV-cluster-dev
```

#### 3. `status-page-infra/.github/workflows/gitops-sync.yml`

```yaml
# ליין 18 - עדכן שם קלאסטר
EKS_CLUSTER_NAME: Nadav-Statuspage-Project-DEV-cluster-dev
```

---

## 7️⃣ וידוא שכל דבר קיים ב-AWS

### checklist:

```bash
# ✅ ECR Repository קיים
aws ecr describe-repositories --repository-names nadav-statuspage

# ✅ EKS Cluster קיים ופעיל
aws eks describe-cluster --name Nadav-Statuspage-Project-DEV-cluster-dev

# ✅ RDS & Redis קיימים (מ-values.yaml)
# DB: nadav-statuspage-project-dev-db.cx248m4we6k7.us-east-1.rds.amazonaws.com
# Redis: nadav-statuspage-project-dev-redis.7fftml.ng.0001.use1.cache.amazonaws.com

# ✅ IAM Role קיים
aws iam get-role --role-name github-actions-eks-deployer

# ✅ aws-auth configmap מעודכן
kubectl get configmap aws-auth -n kube-system -o yaml | grep github-actions
```

---

## 8️⃣ בדיקה ראשונית - Test המערכת

### בדיקה 1: CI Pipeline

```bash
# עשה שינוי קטן באפליקציה
cd status-page-app
echo "# Test change" >> README.md
git add README.md
git commit -m "test: CI pipeline"
git push origin main

# עקוב אחרי workflow:
# GitHub → status-page-app → Actions → צפה ב-run
```

**מה אמור לקרות:**
1. ✅ Linting passes
2. ✅ Docker build succeeds
3. ✅ Trivy scan completes
4. ✅ Push to ECR succeeds
5. ✅ Trigger sent to infra repo

### בדיקה 2: CD Pipeline

```bash
# בדוק ש-infra repo קיבל את ה-trigger
# GitHub → status-page-infra → Actions → צפה ב-cd-deploy run
```

**מה אמור לקרות:**
1. ✅ values.yaml מתעדכן עם SHA חדש
2. ✅ Commit נוצר ב-Git
3. ✅ Helm deploy מצליח
4. ✅ Pods עולים ב-EKS

### בדיקה 3: GitOps Sync

```bash
# עשה שינוי ידני ב-values.yaml
cd status-page-infra
# שנה משהו ב-helm-statuspage/values.yaml
git add .
git commit -m "test: gitops sync"
git push origin main

# תוך 5 דקות, GitOps sync צריך לרוץ אוטומטית
# GitHub → Actions → gitops-sync
```

---

## 9️⃣ Troubleshooting שגיאות נפוצות

### שגיאה: `Error: Credentials could not be loaded`

**פתרון:**
```bash
# בדוק ש-AWS_ROLE_ARN נמצא ב-GitHub Secrets
# בדוק שה-Trust Policy של ה-Role נכון:

aws iam get-role --role-name github-actions-eks-deployer --query 'Role.AssumeRolePolicyDocument'

# ודא שיש שם:
# "Federated": "arn:aws:iam::992382545251:oidc-provider/token.actions.githubusercontent.com"
# "Condition": { "StringLike": { "token.actions.githubusercontent.com:sub": "repo:YOUR_USERNAME/*" }}
```

### שגיאה: `Error: User is not authorized to perform: eks:DescribeCluster`

**פתרון:**
```bash
# ה-IAM Role צריך הרשאות EKS
# בדוק שה-policy מצורפת:

aws iam list-attached-role-policies --role-name github-actions-eks-deployer

# אם חסר, צרף:
aws iam attach-role-policy \
  --role-name github-actions-eks-deployer \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

### שגיאה: `error: You must be logged in to the server (Unauthorized)`

**פתרון:**
```bash
# ה-Role לא ב-aws-auth configmap
kubectl edit configmap aws-auth -n kube-system

# הוסף:
- rolearn: arn:aws:iam::992382545251:role/github-actions-eks-deployer
  username: github-actions-deployer
  groups:
    - system:masters
```

### שגיאה: `Error: repository_dispatch failed`

**פתרון:**
```bash
# PAT_TOKEN לא נכון או חסר הרשאות
# צור token חדש עם repo + workflow scopes
# עדכן את ה-Secret ב-GitHub
```

### שגיאה: `Helm upgrade failed: release not found`

**פתרון:**
```bash
# זה ה-deploy הראשון, Helm לא מוצא release קיים
# זה בסדר! helm upgrade --install יוצר אותו בפעם הראשונה
# אם יש שגיאה אחרת, בדוק:

helm list -n default
kubectl get pods -n default
kubectl get events -n default --sort-by='.lastTimestamp'
```

---

## 🎯 סיכום - Checklist מלא

לפני Push:
- [ ] OIDC Provider קיים ב-AWS
- [ ] IAM Role נוצר עם הרשאות ECR + EKS
- [ ] Role נוסף ל-aws-auth configmap
- [ ] PAT Token נוצר ב-GitHub
- [ ] AWS_ROLE_ARN ב-Secrets של שני ה-repos
- [ ] PAT_TOKEN ב-Secrets של שני ה-repos
- [ ] שמות קלאסטר עודכנו ב-workflows
- [ ] Repository names עודכנו ב-workflow triggers
- [ ] ECR Repository קיים
- [ ] EKS Cluster פעיל
- [ ] RDS + Redis פעילים

אחרי Push ראשון:
- [ ] CI Pipeline עבר בהצלחה
- [ ] Image הועלה ל-ECR
- [ ] CD Pipeline רץ אוטומטית
- [ ] values.yaml התעדכן ב-Git
- [ ] Pods עולים ב-EKS
- [ ] GitOps Sync רץ every 5 minutes

---

## 📞 זקוק לעזרה?

1. **בדוק Logs:**
   - GitHub Actions logs
   - kubectl logs
   - Helm status

2. **בדוק Configuration:**
   - IAM Role Trust Policy
   - aws-auth ConfigMap
   - GitHub Secrets

3. **פתרון בעיות נפוץ:**
   - אתה חייב ARM של ROLE ולא של USER
   - Token צריך repo + workflow scopes
   - Region חייב להיות consistent בכל מקום

---

**כשהכל עובד, תראה:**
```
✅ Push → CI → ECR → Auto Deploy → EKS → Live! 🚀
```

זה GitOps אמיתי, בלי Jenkins, בלי ArgoCD!
