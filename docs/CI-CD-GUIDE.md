# CI/CD Guide (GitHub Actions Only)

## מטרת המסמך
המסמך מרכז את כל דרכי ההפעלה של ה-CI/CD, את כל קבצי ה-workflow הרלוונטיים, ואת ההבדל בין עבודה ב-`CI/CD` branch לבין `main`/`develop`.

---

## כל קבצי ה-CI/CD במערכת

### App Repository (`status-page-app`)
- `.github/workflows/app-build.yml`
  - CI מלא: lint + docker build + trivy + push ל-ECR + trigger ל-infra repo.

### Infra Repository (`status-page-infra`)
- `.github/workflows/infra-validate.yml`
  - ולידציה לתשתית: Terraform fmt/init/validate + Helm lint/template.
- `.github/workflows/cd-deploy.yml`
  - CD ל-EKS דרך Helm.
- `.github/workflows/gitops-sync.yml`
  - GitOps sync אוטומטי + drift detection.

---

## דרכי פעולה (Operating Modes)

## 1) Full CI from App repo
**קובץ:** `status-page-app/.github/workflows/app-build.yml`

**טריגרים:**
- `push` על `main`, `develop`, `CI/CD`
- `pull_request` על `main`, `develop`, `CI/CD`

**מה קורה:**
1. lint לקוד פייתון
2. build לאימג' דוקר
3. סריקת אבטחה (Trivy)
4. push ל-ECR (ב-push)
5. `repository_dispatch` ל-`status-page-infra`

**מתי להשתמש:**
- שינויי אפליקציה.
- כל פעם שרוצים לפרסם image חדש ל-ECR.

---

## 2) Auto CD by Dispatch (App → Infra)
**קובץ:** `status-page-infra/.github/workflows/cd-deploy.yml`

**טריגר:**
- `repository_dispatch` עם `event-type: update-image`

**מה קורה:**
1. קבלת `image_tag` מה-app repo
2. עדכון `helm-statuspage/values.yaml`
3. commit/push ל-infra repo (GitOps source of truth)
4. deploy ל-EKS עם `helm upgrade --install --atomic`
5. ולידציה בסיסית (`pods`, `service`, `ingress`)

**מתי להשתמש:**
- זרימת production/staging רגילה אחרי build מוצלח.

---

## 3) Manual CD (Hotfix / Rollback)
**קובץ:** `status-page-infra/.github/workflows/cd-deploy.yml`

**טריגר:**
- `workflow_dispatch`

**מה קורה:**
- מפעילים ידנית מה-UI עם `image_tag` רצוי (למשל SHA ישן לרולבק).

**מתי להשתמש:**
- rollback מהיר.
- deploy של תג ספציפי בלי לחכות ל-pipeline המלא.

---

## 4) Direct CD Test from CI/CD Branch
**קובץ:** `status-page-infra/.github/workflows/cd-deploy.yml`

**טריגר:**
- `push` על branch `CI/CD`
- רק אם היה שינוי ב:
  - `helm-statuspage/**`
  - `.github/workflows/cd-deploy.yml`

**מה קורה:**
- deploy ישיר לערך `image.tag` הקיים ב-`values.yaml`.
- במצב זה לא מתבצע עדכון אוטומטי ל-tag ולא commit נוסף.

**מתי להשתמש:**
- בדיקות pipeline ו-deploy לפני merge ל-`main`.

---

## 5) GitOps Auto Sync (ArgoCD Alternative)
**קובץ:** `status-page-infra/.github/workflows/gitops-sync.yml`

**טריגרים:**
- `push` על `main` ו-`CI/CD` עבור `helm-statuspage/**`
- `schedule` כל 5 דקות
- `workflow_dispatch`

**מה קורה:**
1. משווה `image.tag` בין מצב פרוס (Helm values) לבין Git
2. אם יש drift → מבצע sync עם Helm
3. בודק health של הפודים

**מתי להשתמש:**
- שמירה על התאמה רציפה בין Git לקלאסטר.
- תחליף מעשי ל-ArgoCD בסביבת MVP/פרויקט גמר.

---

## 6) Infra Validation (Quality Gate)
**קובץ:** `status-page-infra/.github/workflows/infra-validate.yml`

**טריגרים:**
- `push` על `main`, `develop`, `CI/CD`
- `pull_request` על `main`, `develop`

**מה קורה:**
- בדיקות פורמט/תקינות ל-Terraform
- lint/template ל-Helm

**מתי להשתמש:**
- לפני merge לתשתיות.

---

## מטריצת טריגרים מהירה

| Workflow | main | develop | CI/CD | PR | Schedule | Manual | Dispatch |
|---|---|---|---|---|---|---|---|
| app-build.yml | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| infra-validate.yml | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| cd-deploy.yml | ❌* | ❌ | ✅** | ❌ | ❌ | ✅ | ✅ |
| gitops-sync.yml | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ |

\* על `main` הריצה מגיעה בעיקר דרך `repository_dispatch` מה-app pipeline.  
\** על `CI/CD` רץ רק אם יש שינוי ב-`helm-statuspage/**` או ב-`.github/workflows/cd-deploy.yml`.

---

## זרימות מומלצות לפי סביבה

## Development / Testing
1. עובדים בענף `CI/CD`.
2. משנים workflow/helm.
3. `push` → רואים ריצות של CI + validate + CD test.
4. מתקנים עד שהכל ירוק.

## Main / Production Flow
1. merge ל-`main` ב-app repo.
2. `app-build.yml` בונה ודוחף image ל-ECR.
3. dispatch ל-infra repo עם SHA tag.
4. `cd-deploy.yml` מעדכן values + deploy ל-EKS.
5. `gitops-sync.yml` שומר על reconciliation רציף.

---

## דרישות Secrets לשני ה-Repos

חובה להגדיר:
- `AWS_ROLE_ARN`
- `PAT_TOKEN`

המלצה:
- לעבוד עם OIDC בלבד (ללא Access Keys סטטיים).

---

## בדיקות תקינות אחרי Push

## בדיקת CI
- Actions ב-app repo: run של `CI - Build, Scan & Push to ECR`.
- לוודא `Build`, `Trivy`, `ECR push` עברו.

## בדיקת CD
- Actions ב-infra repo: run של `CD - Deploy to EKS`.
- לוודא `Deploy with Helm` ו-`Verify deployment` עברו.

## בדיקת GitOps
- Actions ב-infra repo: run של `GitOps - Auto Sync to EKS`.
- לוודא שאין drift או שהוא תוקן בהצלחה.

---

## תקלות נפוצות

- `AWS credentials` נכשל: בדקו `AWS_ROLE_ARN` ו-Trust policy ל-OIDC.
- `repository_dispatch` נכשל: בדקו `PAT_TOKEN` עם `repo` scope.
- `kubectl unauthorized`: בדקו `aws-auth` ב-EKS.
- `helm upgrade` נכשל: בדקו ערכי secrets/config ו-health של התלויות (RDS/Redis).

---

## סיכום
GitHub Actions מחליף כאן גם CI (במקום Jenkins) וגם GitOps/CD (במקום ArgoCD) עם 3 דרכי הפעלה פרקטיות:
1. אוטומטי מה-app pipeline (dispatch)
2. ידני (`workflow_dispatch`)
3. בדיקות ישירות מענף `CI/CD` (push-based)

כך אפשר להתקדם מהר בפיתוח, ועדיין לשמור על תהליך release נקי ומבוקר ל-`main`.
