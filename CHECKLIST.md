# ✅ Checklist - GitHub Actions CI/CD Setup

הדפס דף זה ועבור צעד אחר צעד. סמן V כשסיימת כל שלב.

---

## 📋 Phase 1: AWS Infrastructure (Terraform)

### IAM & OIDC Setup
- [ ] פתח את `Terraform/environments/dev/main.tf`
- [ ] הוסף את module `github-actions-iam` (ראה example.tf)
- [ ] עדכן את `github_org` עם שם המשתמש שלך ב-GitHub
- [ ] `terraform init`
- [ ] `terraform plan` - ודא שהכל נראה טוב
- [ ] `terraform apply` - אשר בהקלדת "yes"
- [ ] העתק את `github_actions_role_arn` מ-output
- [ ] שמור את ה-ARN במקום בטוח (תצטרך אותו!)

```
✍️ ARN שקיבלתי:
arn:aws:iam::____________________:role/________________________
```

---

## 📋 Phase 2: Kubernetes Configuration

### Update aws-auth ConfigMap
- [ ] הרץ: `kubectl get nodes` - ודא שיש חיבור ל-EKS
- [ ] הרץ: `kubectl edit configmap aws-auth -n kube-system`
- [ ] הוסף את ה-Role ל-mapRoles (העתק מ-SETUP-GUIDE.md)
- [ ] שמור וצא (`:wq`)
- [ ] הרץ: `kubectl get configmap aws-auth -n kube-system -o yaml | grep github`
- [ ] ודא שאתה רואה את ה-Role שהוספת

---

## 📋 Phase 3: GitHub Personal Access Token (PAT)

### Create PAT
- [ ] פתח: https://github.com/settings/tokens/new
- [ ] שם Token: "CI/CD Pipeline"
- [ ] בחר Expiration (המלצה: 90 days)
- [ ] סמן scope: `repo` (כל ה-checkboxes מתחת)
- [ ] סמן scope: `workflow`
- [ ] לחץ "Generate token"
- [ ] **העתק את ה-Token מיד!** (לא תראה אותו שוב)

```
✍️ PAT Token שקיבלתי:
ghp_________________________________________
```

---

## 📋 Phase 4: GitHub Secrets Configuration

### Repository: status-page-app
- [ ] לך ל: https://github.com/YOUR_USERNAME/status-page-app/settings/secrets/actions
- [ ] לחץ "New repository secret"
- [ ] Secret #1:
    - Name: `AWS_ROLE_ARN`
    - Value: [הדבק את ה-ARN שהעתקת]
    - לחץ "Add secret"
- [ ] Secret #2:
    - Name: `PAT_TOKEN`
    - Value: [הדבק את ה-PAT שהעתקת]
    - לחץ "Add secret"
- [ ] ודא ששני ה-Secrets מופיעים ברשימה

### Repository: status-page-infra
- [ ] לך ל: https://github.com/YOUR_USERNAME/status-page-infra/settings/secrets/actions
- [ ] לחץ "New repository secret"
- [ ] Secret #1:
    - Name: `AWS_ROLE_ARN`
    - Value: [הדבק את ה-ARN שהעתקת]
    - לחץ "Add secret"
- [ ] Secret #2:
    - Name: `PAT_TOKEN`
    - Value: [הדבק את ה-PAT שהעתקת]
    - לחץ "Add secret"
- [ ] ודא ששני ה-Secrets מופיעים ברשימה

---

## 📋 Phase 5: Update Workflow Files

### status-page-app/.github/workflows/app-build.yml
- [ ] פתח את הקובץ בעורך
- [ ] מצא שורה: `repository: ${{ github.repository_owner }}/status-page-infra`
- [ ] החלף `${{ github.repository_owner }}` עם שם המשתמש שלך
- [ ] דוגמה: `repository: nadavbh/status-page-infra`
- [ ] שמור
- [ ] commit & push

### status-page-infra/.github/workflows/cd-deploy.yml
- [ ] פתח את הקובץ בעורך
- [ ] מצא: `EKS_CLUSTER_NAME: Nadav-Statuspage-Project-DEV-cluster-dev`
- [ ] עדכן את שם הקלאסטר שלך
- [ ] שמור

```
✍️ שם קלאסטר EKS שלי:
_________________________________________________________________
```

### status-page-infra/.github/workflows/gitops-sync.yml
- [ ] פתח את הקובץ בעורך
- [ ] מצא: `EKS_CLUSTER_NAME: Nadav-Statuspage-Project-DEV-cluster-dev`
- [ ] עדכן את שם הקלאסטר שלך (אותו שם כמו למעלה)
- [ ] שמור
- [ ] commit & push

---

## 📋 Phase 6: Test the Pipeline

### Test #1: CI Pipeline
- [ ] `cd status-page-app`
- [ ] `echo "# Test" >> README.md`
- [ ] `git add .`
- [ ] `git commit -m "test: CI pipeline"`
- [ ] `git push origin main`
- [ ] לך ל: https://github.com/YOUR_USERNAME/status-page-app/actions
- [ ] מצא את workflow הרץ האחרון
- [ ] ודא שכל השלבים עברו ✅:
    - [ ] Linting
    - [ ] Build Docker image
    - [ ] Trivy security scan
    - [ ] Push to ECR
    - [ ] Trigger Infrastructure Update

### Test #2: CD Pipeline
- [ ] לך ל: https://github.com/YOUR_USERNAME/status-page-infra/actions
- [ ] צפה ב-workflow "CD - Deploy to EKS"
- [ ] ודא שכל השלבים עברו ✅:
    - [ ] Update values.yaml
    - [ ] Commit and push
    - [ ] Deploy with Helm
    - [ ] Verify deployment
    - [ ] Get Ingress URL

### Test #3: Verify on EKS
- [ ] `kubectl get pods -n default -l app.kubernetes.io/name=statuspage`
- [ ] ודא שרואה pods ב-status `Running`
- [ ] `kubectl get svc -n default`
- [ ] `kubectl get ingress -n default`
- [ ] העתק את ה-ALB hostname
- [ ] פתח בדפדפן: `http://<alb-hostname>`
- [ ] ודא שהאפליקציה עובדת! 🎉

```
✍️ ALB URL שלי:
http://___________________________________________________________
```

---

## 📋 Phase 7: GitOps Sync Test

### Test Auto-Sync
- [ ] `cd status-page-infra`
- [ ] ערוך `helm-statuspage/values.yaml`
- [ ] שנה `replicaCount: 2` ל- `replicaCount: 3`
- [ ] `git add .`
- [ ] `git commit -m "test: increase replicas"`
- [ ] `git push origin main`
- [ ] המתן מקסימום 5 דקות
- [ ] לך ל-Actions → "GitOps - Auto Sync to EKS"
- [ ] ודא ש-workflow רץ וזיהה את השינוי
- [ ] `kubectl get pods -n default -l app=statuspage-web`
- [ ] ודא שיש עכשיו 3 pods (במקום 2)

---

## 📋 Phase 8: Final Verification

### Checklist סופי
- [ ] CI Pipeline עובד ✅
- [ ] CD Pipeline עובד ✅
- [ ] GitOps Sync עובד ✅
- [ ] Pods רצים ב-EKS ✅
- [ ] Application נגישה דרך ALB ✅
- [ ] Helm release מותקן: `helm list -n default` ✅
- [ ] Ingress מוגדר: `kubectl get ingress -n default` ✅

### Test E2E Flow
- [ ] עשה שינוי קטן בקוד (למשל עדכן README)
- [ ] `git push origin main`
- [ ] צפה איך GitHub Actions:
    1. בונה את ה-image
    2. דוחף ל-ECR
    3. מעדכן את infra repo
    4. מפרס ל-EKS
    5. הפודים מתעדכנים
- [ ] ודא שהשינוי נראה באפליקציה

---

## 🎉 Success Criteria

כשכל התיבות מסומנות, הצלחת! יש לך:

✅ **CI Pipeline** - Build, Test, Scan, Push  
✅ **CD Pipeline** - Auto-deploy to EKS  
✅ **GitOps** - Auto-sync every 5 minutes  
✅ **Security** - OIDC (no Access Keys)  
✅ **Zero Maintenance** - No Jenkins/ArgoCD servers  

---

## 🆘 אם משהו לא עובד

### אם CI נכשל:
1. בדוק GitHub Actions logs
2. ראה SETUP-GUIDE.md → Troubleshooting
3. ודא ש-AWS_ROLE_ARN נכון

### אם CD נכשל:
1. בדוק EKS cluster name
2. בדוק aws-auth configmap
3. `kubectl get events --sort-by='.lastTimestamp'`

### אם GitOps לא מסנכרן:
1. בדוק שה-workflow enabled
2. Actions → gitops-sync → Enable workflow
3. הרץ ידנית פעם אחת

---

## 📝 Notes

השתמש בשטח הזה לרשום הערות, שגיאות, או דברים שצריך לזכור:

```
_______________________________________________________________________________

_______________________________________________________________________________

_______________________________________________________________________________

_______________________________________________________________________________

_______________________________________________________________________________
```

---

**תאריך התחלה:** _______________  
**תאריך סיום:** _______________  
**סטטוס:** [ ] בתהליך   [ ] הושלם ✅

---

**Good luck!** 🚀
