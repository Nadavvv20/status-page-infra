# 🆘 Troubleshooting - Failures ב-CI/CD Workflows

## 🔴 הבעיה: Workflows נכשלים ב-GitHub Actions

מן התמונה אני רואה כמה failures:
- PR #2 (CI/CD) - נכשל
- "Fix workflow YAML syntax" - נכשל
- "Fix Django version" - נכשל

## 🔍 הגורמים הסבירים (בסדר עדיפויות):

### 1️⃣ **Secrets לא הוגדרו** ⚠️ הסבירות הגבוהה ביותר
### 2️⃣ **OIDC Provider/IAM Role לא קיימים** ב-AWS
### 3️⃣ **Dockerfile בעיות** או dependencies ב-requirements.txt
### 4️⃣ **ECR Repository לא קיימים**

---

## ✅ תקנו בעיות - צעד אחר צעד

### שלב 0: וודא את הבסיס (מיידי)

```bash
# 1. וודא שאתה בענף CI/CD
git branch
# Output: * CI/CD

# 2. וודא שה-repo זה Nadavvv20
git remote -v
# Output: ... github.com/Nadavvv20/status-page-app ...
```

---

### שלב 1: הוסף Secrets ל-App Repo (חובה!)

**זה הכי ממש ההסתברות שלא הוגדר!**

#### ב-GitHub App Repo:
```
https://github.com/Nadavvv20/status-page-app
  ↓
Settings → Secrets and variables → Actions
  ↓
New Repository Secret
```

**Secret 1: AWS_ROLE_ARN**
```
Name: AWS_ROLE_ARN
Value: arn:aws:iam::992382545251:role/github-actions-eks-deployer
```

**Secret 2: PAT_TOKEN**
```
Name: PAT_TOKEN
Value: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> ⚠️ אם אתה לא יודע מה הM ARN או Token:
> - ARN: יוצרים דרך Terraform module (ראה SETUP-GUIDE.md)
> - Token: יוצרים ב- https://github.com/settings/tokens/new עם `repo` + `workflow`

---

### שלב 2: וודא AWS Resources קיימים

```bash
# בדוק OIDC Provider
aws iam list-open-id-connect-providers

# בדוק IAM Role
aws iam get-role --role-name github-actions-eks-deployer

# בדוק ECR Repository
aws ecr describe-repositories --repository-names nadav-statuspage
```

אם משהו חסר, הרץ את Terraform module:
```bash
cd status-page-infra/Terraform/environments/dev
terraform apply
```

---

### שלב 3: וודא Dockerfile & Requirements

```bash
# בדוק שקובץ ה-Dockerfile קיים בשורש
ls -la Dockerfile

# בדוק requirements.txt
cat requirements.txt | head -20
```

---

### שלב 4: בדוק את ה-Workflow עצמו

```bash
# וודא שה-workflow syntax נכון
# (GitHub כבר עדן עם סימן חירום אם יש בעיה)

# לוודא ידנית:
# GitHub → status-page-app → Actions → CI - Build, Scan & Push to ECR
# → בדוק את ה-error log בה-failed run
```

---

## 📋 Checklist לתיקון

### AWS Infrastructure
- [ ] OIDC Provider קיים ב-AWS
- [ ] IAM Role `github-actions-eks-deployer` קיים
- [ ] Trust Policy נכון (קשור ל-OIDC + GitHub repos)
- [ ] ECR Repository `nadav-statuspage` קיים

### GitHub Secrets (App Repo)
- [ ] `AWS_ROLE_ARN` מוגדר
- [ ] `PAT_TOKEN` מוגדר

### GitHub Secrets (Infra Repo)
- [ ] `AWS_ROLE_ARN` מוגדר
- [ ] `PAT_TOKEN` מוגדר

### Local Repo
- [ ] Dockerfile קיים
- [ ] requirements.txt עדכון
- [ ] .github/workflows/app-build.yml תקין

---

## 🔧 דרך מהירה לתקנות Secrets ב-GitHub

### דרך 1: דרך UI (הכי קל)
```
1. https://github.com/Nadavvv20/status-page-app/settings/secrets/actions
2. Click "New repository secret"
3. הדבק את שני ה-values
4. Save
```

### דרך 2: דרך GitHub CLI (אם יש gh)
```bash
gh secret set AWS_ROLE_ARN -b "arn:aws:iam::..."
gh secret set PAT_TOKEN -b "ghp_..."
```

---

## 🚨 Error Messages שעלולים להופיע ופתרונות

### Error: "Error: Credentials could not be loaded"
```
בעיה: AWS_ROLE_ARN לא מוגדר או שגוי
פתרון: בדוק שה-Secret מוגדר בדיוק:
1. GitHub → Settings → Secrets
2. וודא שה-Name הוא AWS_ROLE_ARN (exact)
3. וודא שה-Value הוא ה-ARN המלא
```

### Error: "Error: User is not authorized"
```
בעיה: Trust Policy של ה-Role לא מכיל את GitHub
פתרון:
1. בדוק את ה-Trust Policy:
   aws iam get-role --role-name github-actions-eks-deployer
2. ודא שזה מכיל:
   "Federated": "arn:aws:iam::992382545251:oidc-provider/token.actions.githubusercontent.com"
   "Condition": { "StringLike": { "token.actions.githubusercontent.com:sub": "repo:Nadavvv20/*" }}
```

### Error: "Cannot find docker"
```
בעיה: Dockerfile לא קיים
פתרון:
1. וודא שה-Dockerfile בשורש של repo:
   ls -la Dockerfile
2. אם חסר, העתק מהר-infra
```

### Error: "Module not found"
```
בעיה: dependencies לא מותקנים
פתרון:
1. בדוק requirements.txt
2. בדוק שהוא בשורש:
   ls -la requirements.txt
3. בדוק שה-workflow רץ pip install נכון
```

---

## 📊 דיאגנוזה מהירה

בואו נעלה את סדרת הבדיקות הזו כדי להבין בדיוק מה קרוע:

```bash
# הרץ את כל אלה ברצף
echo "=== Repo Status ==="
git status
git remote -v

echo "=== Local Files ==="
ls -la Dockerfile requirements.txt

echo "=== AWS OIDC Provider ==="
aws iam list-open-id-connect-providers 2>&1 | grep -i github

echo "=== IAM Role ==="
aws iam get-role --role-name github-actions-eks-deployer 2>&1 | head -5

echo "=== ECR ==="
aws ecr describe-repositories --repository-names nadav-statuspage 2>&1 | grep repositoryUri
```

---

## 🎯 Next Steps

1. **ודא שיש AWS credentials** בשורת הפקודה (אחרת בדיקות AWS לא יעבדו)
2. **הוסף את שני ה-Secrets** ל-GitHub (זה כנראה ה-bug העיקרי)
3. **דחוף commit נוסף** כדי לזרז retry:
   ```bash
   git commit --allow-empty -m "ci: retry workflow with secrets"
   git push origin CI/CD
   ```
4. **צפה ב-Actions** כדי לראות אם הריצה החדשה עובדת

---

## 💬 אם עדיין נתקעת:

שלח את:
1. **הודעת השגיאה המלאה** מ-GitHub Actions
2. **הוצא מ-AWS**:
   ```bash
   aws iam list-open-id-connect-providers
   aws iam get-role --role-name github-actions-eks-deployer --query 'Role.AssumeRolePolicyDocument'
   ```
3. **כתובת של GitHub Secrets** (מה בדיוק מוגדר)

---

**זיכרון:** הבעיה 90% של הזמן היא עם Secrets או OIDC!
