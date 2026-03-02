# CI/CD Pipeline with GitHub Actions

## 🎯 סקירה כללית

הפרויקט משתמש ב-**GitHub Actions טהור** עבור CI/CD, ומחליף את הצורך ב-Jenkins ו-ArgoCD.

### ✅ GitHub Actions מחליף:
- **Jenkins** → CI Pipeline עם Build, Test, Scan, Push
- **ArgoCD** → GitOps Sync עם drift detection ואוטומציה

---

## 📁 מבנה Workflows

### Repo: `status-page-app`
```
.github/workflows/
└── app-build.yml        # CI Pipeline - Build → Scan → Push → Trigger
```

### Repo: `status-page-infra`
```
.github/workflows/
├── cd-deploy.yml        # CD Pipeline - Deploy to EKS
├── gitops-sync.yml      # GitOps Auto-Sync (ArgoCD replacement)
└── infra-validate.yml   # Terraform & Helm validation
```

---

## 🔄 תהליך ה-CI/CD המלא

## 1️⃣ **CI Pipeline** (`app-build.yml`)

### טריגרים:
- Push ל-`main` או `develop`
- Pull Request ל-`main` או `develop`

### שלבים:

```yaml
1. Linting (Python Code Quality)
   └── flake8 לבדיקת תקינות קוד

2. Build Docker Image
   └── בניית image עם SHA commit כ-tag

3. Security Scan (Trivy)
   └── סריקת פגיעויות CRITICAL & HIGH

4. Push to ECR
   └── העלאה ל-Amazon ECR (רק ב-main/develop)

5. Trigger Infrastructure Update
   └── שליחת repository_dispatch ל-infra repo
```

### יתרונות על פני Jenkins:
✅ אין צורך בתחזוקה של שרת Jenkins  
✅ סקיילינג אוטומטי של Runners  
✅ אינטגרציה מובנית עם GitHub  
✅ OIDC authentication ל-AWS (ללא Access Keys)  

---

## 2️⃣ **CD Pipeline** (`cd-deploy.yml`)

### טריגרים:
- `repository_dispatch` מ-app repo
- Manual trigger (`workflow_dispatch`)

### שלבים:

```yaml
1. Update values.yaml
   └── עדכון image tag ב-Helm chart

2. Commit & Push changes
   └── שמירת השינוי ב-Git (GitOps pattern)

3. Configure AWS & EKS
   └── התחברות ל-EKS cluster

4. Deploy with Helm
   └── helm upgrade --install --atomic

5. Verify Deployment
   └── בדיקת pods, services, ingress
```

### מה קורה כאן?
1. **App repo** דוחף code → GitHub Actions בונה image → שולח event
2. **Infra repo** מקבל event → מעדכן values.yaml → מפרס ל-EKS
3. **Git = Source of Truth** (GitOps principle)

---

## 3️⃣ **GitOps Auto-Sync** (`gitops-sync.yml`)

### טריגרים:
- Push ל-`helm-statuspage/**` (שינוי במניפסטים)
- Schedule: כל 5 דקות (כמו ArgoCD)
- Manual trigger

### שלבים:

```yaml
1. Check Drift
   └── השוואת deployed values מול Git

2. Sync if Needed
   └── Helm upgrade אם יש הבדל

3. Verify Health
   └── בדיקת pods status
```

### יתרונות על פני ArgoCD:
✅ אין צורך בהתקנה של ArgoCD בקלאסטר  
✅ פחות משאבים (CPU/Memory)  
✅ קונפיגורציה פשוטה יותר  
✅ אותם עקרונות GitOps  
⚠️ **חיסרון**: UI פחות מתקדם (אבל יש GitHub UI)

---

## 🔐 הגדרות אבטחה נדרשות

### ב-AWS:
```hcl
# יצירת OIDC Provider ל-GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [...]
}

# יצירת IAM Role עם Trust Policy
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-eks-deployer"
  
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_ORG/status-page-app:ref:refs/heads/main",
            "repo:YOUR_ORG/status-page-infra:ref:refs/heads/main"
          ]
        }
      }
    }]
  })
}

# הרשאות: ECR, EKS, Helm
resource "aws_iam_role_policy_attachment" "github_actions_policy" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/..." # ECR + EKS
}
```

### ב-GitHub:

#### **Secrets נדרשים** (Settings → Secrets → Actions):

**status-page-app repo:**
```
AWS_ROLE_ARN = arn:aws:iam::992382545251:role/github-actions-eks-deployer
PAT_TOKEN = ghp_xxxxxxxxxxxx (Personal Access Token עם repo scope)
```

**status-page-infra repo:**
```
AWS_ROLE_ARN = arn:aws:iam::992382545251:role/github-actions-eks-deployer
PAT_TOKEN = ghp_xxxxxxxxxxxx
```

#### איך ליצור PAT (Personal Access Token):
1. GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. Select scopes: `repo` (full control)
4. Copy ושמור ב-Secrets

---

## 🚀 איך להריץ את ה-Pipeline

### הפעלה אוטומטית:
```bash
# 1. עדכן קוד באפליקציה
cd status-page-app
git add .
git commit -m "New feature"
git push origin main

# → GitHub Actions אוטומטית:
#    ✓ בונה image
#    ✓ סורק אבטחה  
#    ✓ דוחף ל-ECR
#    ✓ מפעיל deployment ב-infra repo
#    ✓ מפרס ל-EKS

# 2. GitOps Sync כל 5 דקות
# → בודק drift ומסנכרן אוטומטית
```

### הפעלה ידנית:
```bash
# דרך GitHub UI:
1. לך ל-Actions tab
2. בחר workflow (cd-deploy או gitops-sync)
3. לחץ "Run workflow"
4. בחר image tag (או השאר default)
```

---

## 📊 השוואה: GitHub Actions vs Jenkins vs ArgoCD

| תכונה | GitHub Actions | Jenkins | ArgoCD |
|--------|---------------|---------|--------|
| **אירוח** | SaaS (Managed) | Self-hosted | Self-hosted |
| **תחזוקה** | ✅ אפס | ❌ רבה | ⚠️ בינונית |
| **סקיילינג** | ✅ אוטומטי | ❌ ידני | ✅ אוטומטי |
| **אבטחה** | ✅ OIDC | ⚠️ Access Keys | ✅ ServiceAccount |
| **GitOps** | ✅ כן | ❌ לא | ✅ כן |
| **UI** | ⚠️ בסיסי | ✅ מורכב | ✅ מתקדם |
| **עלות** | 💰 חינם/זול | 💰💰 יקר | 💰 חינם |

---

## 🎓 עקרונות GitOps ש-GitHub Actions מממש

1. ✅ **Declarative** - כל המצב מוגדר ב-YAML
2. ✅ **Versioned** - Git הוא מקור האמת
3. ✅ **Immutable** - Image tags עם SHA
4. ✅ **Pulled Automatically** - Auto-sync כל 5 דקות
5. ✅ **Continuously Reconciled** - Drift detection

---

## 🔍 מעקב אחר deployments

### דרך GitHub UI:
```
Repository → Actions → בחר workflow run → ראה לוגים
```

### דרך kubectl:
```bash
# pod status
kubectl get pods -n default -l app.kubernetes.io/name=statuspage

# deployment history
helm history statuspage -n default

# logs
kubectl logs -n default -l app=statuspage-web --tail=100
```

---

## 🛠️ Troubleshooting

### CI נכשל:
```bash
# בדוק את ה-workflow logs ב-GitHub Actions
# שגיאות נפוצות:
- Docker build failed → בדוק Dockerfile
- Trivy found CRITICAL → שדרג dependencies
- ECR push failed → בדוק AWS credentials
```

### CD נכשל:
```bash
# בדוק Helm deployment
helm list -n default
kubectl get events -n default --sort-by='.lastTimestamp'

# בדוק pods
kubectl describe pod <pod-name> -n default
```

### GitOps לא מסנכרן:
```bash
# הרץ ידנית:
# Actions → gitops-sync → Run workflow

# בדוק אם schedule פועל:
# Actions → gitops-sync → ראה runs אחרונים
```

---

## 📚 קריאה נוספת

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GitOps Principles](https://opengitops.dev/)

---

## ✨ סיכום

**GitHub Actions מחליף בהצלחה את Jenkins ו-ArgoCD:**

✅ **CI** - Build, Test, Scan, Push (במקום Jenkins)  
✅ **CD** - Deploy to Kubernetes (במקום manual helm)  
✅ **GitOps** - Auto-sync עם drift detection (במקום ArgoCD)  
✅ **אבטחה** - OIDC ללא secrets (Least Privilege)  
✅ **פשטות** - הכל ב-Git, אין שרתים חיצוניים  

**המלצה**: התחל עם GitHub Actions, ועבור ל-ArgoCD רק אם צריך UI מתקדם או multi-cluster management.
