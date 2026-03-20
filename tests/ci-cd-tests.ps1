#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CI/CD Unit Tests - Validates the entire CI/CD pipeline without deploying or pushing images.
.DESCRIPTION
    Runs comprehensive validations:
    1. Helm chart structure and linting
    2. Helm template rendering
    3. Terraform format and validation
    4. values.yaml structure integrity
    5. GitHub Actions workflow syntax
    6. Script file integrity
    7. File reference consistency across the pipeline
.EXAMPLE
    .\tests\ci-cd-tests.ps1
#>

param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Continue"
$totalTests = 0
$passedTests = 0
$failedTests = 0
$skippedTests = 0
$failures = @()

function Test-Result($name, $passed, $detail = "") {
    $script:totalTests++
    if ($passed) {
        $script:passedTests++
        Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
        Write-Host $name
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
        Write-Host "$name" -NoNewline
        if ($detail) { Write-Host " - $detail" -ForegroundColor DarkGray } else { Write-Host "" }
        $script:failures += "$name : $detail"
    }
}

function Test-Skip($name, $reason) {
    $script:totalTests++
    $script:skippedTests++
    Write-Host "  [SKIP] " -ForegroundColor Yellow -NoNewline
    Write-Host "$name - $reason"
}

function Write-Section($title) {
    Write-Host "`n$('=' * 70)" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
}

# ============================================================================
# TEST GROUP 1: FILE STRUCTURE VALIDATION
# ============================================================================
Write-Section "1. FILE STRUCTURE VALIDATION"

# Required files
$requiredFiles = @(
    "helm-statuspage/Chart.yaml",
    "helm-statuspage/values.yaml",
    "helm-statuspage/templates/_helpers.tpl",
    "helm-statuspage/templates/web-deployment.yaml",
    "helm-statuspage/templates/worker-deployment.yaml",
    "helm-statuspage/templates/scheduler-deployment.yaml",
    "helm-statuspage/templates/service.yaml",
    "helm-statuspage/templates/ingress.yaml",
    "helm-statuspage/templates/hpa.yaml",
    "helm-statuspage/templates/externalsecret.yaml",
    "helm-statuspage/templates/clustersecretstore.yaml",
    "helm-statuspage/templates/serviceaccount.yaml",
    ".github/workflows/cd-deploy.yml",
    ".github/workflows/infra-validate.yml",
    ".github/workflows/gitops-sync.yml",
    "scripts/update-image-tag.ps1",
    "scripts/update-image-tag.sh",
    "Terraform/modules/sg.tf",
    "Terraform/modules/vpc.tf",
    "Terraform/modules/eks.tf",
    "Terraform/modules/rds.tf",
    "Terraform/modules/elasticache.tf",
    "Terraform/modules/iam.tf",
    "Terraform/modules/secrets.tf",
    "Terraform/modules/configmap.tf",
    "Terraform/modules/variables.tf",
    "Terraform/modules/outputs.tf",
    "Terraform/environments/dev/main.tf",
    "Terraform/environments/dev/providers.tf",
    "Terraform/environments/dev/variables.tf",
    "Terraform/environments/dev/terraform.tfvars"
)

foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $RootPath $file
    Test-Result "File exists: $file" (Test-Path $fullPath) "File not found"
}

# ============================================================================
# TEST GROUP 2: HELM CHART VALIDATION
# ============================================================================
Write-Section "2. HELM CHART VALIDATION"

# 2a. Chart.yaml structure
$chartYaml = Join-Path $RootPath "helm-statuspage/Chart.yaml"
if (Test-Path $chartYaml) {
    $chartContent = Get-Content $chartYaml -Raw
    Test-Result "Chart.yaml has apiVersion" ($chartContent -match "apiVersion:") "Missing apiVersion"
    Test-Result "Chart.yaml has name" ($chartContent -match "name:\s*statuspage") "name should be 'statuspage'"
    Test-Result "Chart.yaml has version" ($chartContent -match "version:") "Missing version field"
    Test-Result "Chart.yaml has appVersion" ($chartContent -match "appVersion:") "Missing appVersion field"
}

# 2b. values.yaml structure
$valuesYaml = Join-Path $RootPath "helm-statuspage/values.yaml"
if (Test-Path $valuesYaml) {
    $valuesContent = Get-Content $valuesYaml -Raw
    Test-Result "values.yaml has image.repository" ($valuesContent -match "repository:") "Missing image repository"
    Test-Result "values.yaml has image.tag" ($valuesContent -match "tag:\s*""[^""]+""") "Missing or malformed image tag"
    Test-Result "values.yaml has service config" ($valuesContent -match "service:") "Missing service configuration"
    Test-Result "values.yaml has autoscaling config" ($valuesContent -match "autoscaling:") "Missing autoscaling section"
    Test-Result "values.yaml has resource limits" ($valuesContent -match "resources:") "Missing resource limits"
    Test-Result "values.yaml has ingress config" ($valuesContent -match "ingress:") "Missing ingress configuration"
    
    # Extract image tag and validate it looks like a commit SHA or version
    if ($valuesContent -match 'tag:\s*"([^"]+)"') {
        $tag = $Matches[1]
        $isValidTag = ($tag -match '^[a-f0-9]{7,40}$') -or ($tag -match '^\d+\.\d+') -or ($tag -eq "latest") -or ($tag -match '^ci-')
        Test-Result "values.yaml image tag format is valid ($tag)" $isValidTag "Tag '$tag' doesn't match expected format (sha/version/latest/ci-*)"
    }

    # Validate ECR repository format
    if ($valuesContent -match 'repository:\s*(.+)') {
        $repo = $Matches[1].Trim()
        Test-Result "values.yaml ECR repo format valid" ($repo -match '\d+\.dkr\.ecr\..+\.amazonaws\.com/') "ECR repo format unexpected: $repo"
    }

    # Validate replica count
    if ($valuesContent -match 'replicaCount:\s*(\d+)') {
        $replicas = [int]$Matches[1]
        Test-Result "values.yaml replicas >= 1" ($replicas -ge 1) "replicaCount=$replicas (should be >= 1)"
    }
}

# 2c. Helm lint (if helm is installed)
$helmCmd = Get-Command helm -ErrorAction SilentlyContinue
if ($helmCmd) {
    $helmChartPath = Join-Path $RootPath "helm-statuspage"
    $lintResult = helm lint $helmChartPath 2>&1 | Out-String
    $lintPassed = $LASTEXITCODE -eq 0
    Test-Result "Helm lint passes" $lintPassed $lintResult.Trim()

    # Helm template render (dry-run without cluster)
    $templateResult = helm template test-release $helmChartPath 2>&1 | Out-String
    $templatePassed = $LASTEXITCODE -eq 0
    Test-Result "Helm template renders successfully" $templatePassed "Template render failed"

    if ($templatePassed) {
        # Verify key resources appear in rendered output
        Test-Result "Template contains web Deployment" ($templateResult -match "kind: Deployment[\s\S]*?statuspage.*-web") "web Deployment not found in template"
        Test-Result "Template contains worker Deployment" ($templateResult -match "kind: Deployment[\s\S]*?worker") "worker Deployment not found in template"
        Test-Result "Template contains Service" ($templateResult -match "kind: Service") "Service not found in template"
        Test-Result "Template contains Ingress" ($templateResult -match "kind: Ingress") "Ingress not found in template"
        Test-Result "Template contains HPA" ($templateResult -match "kind: HorizontalPodAutoscaler") "HPA not found in template"
        Test-Result "Template contains ServiceAccount" ($templateResult -match "kind: ServiceAccount") "ServiceAccount not found in template"
    }
} else {
    Test-Skip "Helm lint" "helm CLI not installed"
    Test-Skip "Helm template render" "helm CLI not installed"
}

# ============================================================================
# TEST GROUP 3: TERRAFORM VALIDATION
# ============================================================================
Write-Section "3. TERRAFORM VALIDATION"

$tfCmd = Get-Command terraform -ErrorAction SilentlyContinue
if ($tfCmd) {
    # Format check
    $fmtResult = terraform fmt -check -recursive (Join-Path $RootPath "Terraform") 2>&1 | Out-String
    Test-Result "Terraform format check" ($LASTEXITCODE -eq 0) "Run 'terraform fmt -recursive Terraform/' to fix"

    # Init + validate for dev environment
    $devDir = Join-Path $RootPath "Terraform/environments/dev"
    Push-Location $devDir
    $initResult = terraform init -backend=false 2>&1 | Out-String
    $initPassed = $LASTEXITCODE -eq 0
    Test-Result "Terraform init (dev, no backend)" $initPassed "terraform init failed"

    if ($initPassed) {
        $validateResult = terraform validate 2>&1 | Out-String
        Test-Result "Terraform validate (dev)" ($LASTEXITCODE -eq 0) $validateResult.Trim()
    }
    Pop-Location
} else {
    Test-Skip "Terraform format check" "terraform CLI not installed"
    Test-Skip "Terraform init" "terraform CLI not installed"
    Test-Skip "Terraform validate" "terraform CLI not installed"
}

# ============================================================================
# TEST GROUP 4: TERRAFORM CODE STRUCTURE
# ============================================================================
Write-Section "4. TERRAFORM CODE STRUCTURE"

# Check modules/variables.tf has all expected variables
$modVars = Join-Path $RootPath "Terraform/modules/variables.tf"
if (Test-Path $modVars) {
    $varsContent = Get-Content $modVars -Raw
    $expectedVars = @("region", "project_name", "environment", "vpc_cidr", "cluster_name", "instance_types", "db_instance_class", "redis_node_type")
    foreach ($v in $expectedVars) {
        Test-Result "Variable '$v' defined in modules/variables.tf" ($varsContent -match "variable\s+""$v""") "Variable not found"
    }
}

# Check dev/main.tf references the module correctly
$devMain = Join-Path $RootPath "Terraform/environments/dev/main.tf"
if (Test-Path $devMain) {
    $devContent = Get-Content $devMain -Raw
    Test-Result "dev/main.tf references root module" ($devContent -match 'source\s*=\s*"../../modules"') "Module source path incorrect"
    Test-Result "dev/main.tf references helm_releases module" ($devContent -match 'source\s*=\s*"../../modules/helm_releases"') "helm_releases module not referenced"
}

# Check security group references are consistent
$sgFile = Join-Path $RootPath "Terraform/modules/sg.tf"
if (Test-Path $sgFile) {
    $sgContent = Get-Content $sgFile -Raw
    Test-Result "SG: ALB security group defined" ($sgContent -match 'resource\s+"aws_security_group"\s+"alb_sg"') "ALB SG not found"
    Test-Result "SG: RDS security group defined" ($sgContent -match 'resource\s+"aws_security_group"\s+"rds_sg"') "RDS SG not found"
    Test-Result "SG: Redis security group defined" ($sgContent -match 'resource\s+"aws_security_group"\s+"redis_sg"') "Redis SG not found"
    Test-Result "SG: Node ingress rule from ALB only" ($sgContent -match 'source_security_group_id\s*=\s*aws_security_group\.alb_sg\.id') "Node SG should only accept traffic from ALB SG"
    Test-Result "SG: RDS accepts from EKS nodes only" ($sgContent -match 'rds_sg[\s\S]*?security_groups\s*=\s*\[module\.eks\.node_security_group_id\]') "RDS should only accept from EKS nodes"
    Test-Result "SG: Redis accepts from EKS nodes only" ($sgContent -match 'redis_sg[\s\S]*?security_groups\s*=\s*\[module\.eks\.node_security_group_id\]') "Redis should only accept from EKS nodes"
}

# ============================================================================
# TEST GROUP 5: GITHUB ACTIONS WORKFLOW VALIDATION
# ============================================================================
Write-Section "5. GITHUB ACTIONS WORKFLOW VALIDATION"

$workflowDir = Join-Path $RootPath ".github/workflows"

# cd-deploy.yml checks
$cdDeploy = Join-Path $workflowDir "cd-deploy.yml"
if (Test-Path $cdDeploy) {
    $cdContent = Get-Content $cdDeploy -Raw
    Test-Result "cd-deploy: has repository_dispatch trigger" ($cdContent -match "repository_dispatch:") "Missing repository_dispatch trigger"
    Test-Result "cd-deploy: has workflow_dispatch trigger" ($cdContent -match "workflow_dispatch:") "Missing manual trigger"
    Test-Result "cd-deploy: uses OIDC (id-token: write)" ($cdContent -match "id-token:\s*write") "Should use OIDC, not static credentials"
    Test-Result "cd-deploy: uses aws-actions/configure-aws-credentials" ($cdContent -match "aws-actions/configure-aws-credentials") "Missing AWS credential config"
    Test-Result "cd-deploy: uses role-to-assume (no static keys)" ($cdContent -match "role-to-assume:") "Should use role-to-assume for OIDC"
    Test-Result "cd-deploy: deploys with helm upgrade --install" ($cdContent -match "helm upgrade --install") "Missing helm deploy step"
    Test-Result "cd-deploy: uses --atomic flag" ($cdContent -match "--atomic") "Should use --atomic for safe rollback"
    Test-Result "cd-deploy: uses --wait flag" ($cdContent -match "--wait") "Should use --wait for deployment readiness"
    Test-Result "cd-deploy: has verification step" ($cdContent -match "kubectl get pods") "Missing deployment verification"
    Test-Result "cd-deploy: no hardcoded AWS keys" (-not ($cdContent -match "AKIA[A-Z0-9]{16}")) "HARDCODED AWS KEY DETECTED!"
    Test-Result "cd-deploy: references correct chart path" ($cdContent -match "\./helm-statuspage") "Chart path should be ./helm-statuspage"
    
    # Validate cluster name matches
    if ($cdContent -match 'EKS_CLUSTER_NAME:\s*(.+)') {
        $clusterName = $Matches[1].Trim()
        Test-Result "cd-deploy: cluster name set ($clusterName)" ($clusterName.Length -gt 0) "Empty cluster name"
    }
}

# infra-validate.yml checks
$infraValidate = Join-Path $workflowDir "infra-validate.yml"
if (Test-Path $infraValidate) {
    $ivContent = Get-Content $infraValidate -Raw
    Test-Result "infra-validate: triggers on push" ($ivContent -match "push:") "Missing push trigger"
    Test-Result "infra-validate: triggers on pull_request" ($ivContent -match "pull_request:") "Missing PR trigger"
    Test-Result "infra-validate: runs terraform fmt" ($ivContent -match "terraform fmt") "Missing terraform fmt check"
    Test-Result "infra-validate: runs terraform validate" ($ivContent -match "terraform validate") "Missing terraform validate"
    Test-Result "infra-validate: runs helm lint" ($ivContent -match "helm lint") "Missing helm lint"
    Test-Result "infra-validate: runs helm template" ($ivContent -match "helm template") "Missing helm template check"
}

# gitops-sync.yml checks
$gitopsSync = Join-Path $workflowDir "gitops-sync.yml"
if (Test-Path $gitopsSync) {
    $gsContent = Get-Content $gitopsSync -Raw
    Test-Result "gitops-sync: has schedule trigger" ($gsContent -match "schedule:") "Missing schedule trigger"
    Test-Result "gitops-sync: has drift detection" ($gsContent -match "SYNC_NEEDED|drift") "Missing drift detection logic"
    Test-Result "gitops-sync: compares deployed vs git tag" ($gsContent -match "DEPLOYED_TAG|GIT_TAG") "Missing tag comparison"
    Test-Result "gitops-sync: conditional sync on drift" ($gsContent -match "if.*SYNC_NEEDED") "Should only sync when drift detected"
    Test-Result "gitops-sync: has health verification" ($gsContent -match "Verify deployment|pods.*Running") "Missing health check after sync"
}

# ============================================================================
# TEST GROUP 6: SCRIPT INTEGRITY
# ============================================================================
Write-Section "6. SCRIPT INTEGRITY"

# update-image-tag.ps1
$ps1Script = Join-Path $RootPath "scripts/update-image-tag.ps1"
if (Test-Path $ps1Script) {
    $ps1Content = Get-Content $ps1Script -Raw
    Test-Result "update-image-tag.ps1: accepts Tag parameter" ($ps1Content -match '\$Tag') "Missing Tag parameter"
    Test-Result "update-image-tag.ps1: updates values.yaml" ($ps1Content -match 'values\.yaml') "Should update values.yaml"
    Test-Result "update-image-tag.ps1: uses correct branch" ($ps1Content -match 'CI/CD') "Should target CI/CD branch"
    Test-Result "update-image-tag.ps1: validates file existence" ($ps1Content -match 'Test-Path') "Should validate file exists"
}

# update-image-tag.sh
$shScript = Join-Path $RootPath "scripts/update-image-tag.sh"
if (Test-Path $shScript) {
    $shContent = Get-Content $shScript -Raw
    Test-Result "update-image-tag.sh: has shebang line" ($shContent -match '^#!/') "Missing shebang"
    Test-Result "update-image-tag.sh: uses set -euo pipefail" ($shContent -match 'set -euo pipefail') "Missing strict mode"
    Test-Result "update-image-tag.sh: updates values.yaml" ($shContent -match 'values\.yaml') "Should update values.yaml"
    Test-Result "update-image-tag.sh: uses correct branch" ($shContent -match 'CI/CD') "Should target CI/CD branch"
}

# ============================================================================
# TEST GROUP 7: CROSS-FILE CONSISTENCY
# ============================================================================
Write-Section "7. CROSS-FILE CONSISTENCY"

# Check port consistency across files
$valuesContent = if (Test-Path $valuesYaml) { Get-Content $valuesYaml -Raw } else { "" }
$serviceYaml = Join-Path $RootPath "helm-statuspage/templates/service.yaml"
$serviceContent = if (Test-Path $serviceYaml) { Get-Content $serviceYaml -Raw } else { "" }
$webDeployYaml = Join-Path $RootPath "helm-statuspage/templates/web-deployment.yaml"
$webDeployContent = if (Test-Path $webDeployYaml) { Get-Content $webDeployYaml -Raw } else { "" }

# Service maps port 80 -> targetPort 8000
Test-Result "Service targetPort matches container port (8000)" ($serviceContent -match "targetPort:\s*8000") "Service targetPort should be 8000"
Test-Result "Web deployment uses port 8000" ($webDeployContent -match "containerPort:\s*8000") "Container port should be 8000"
Test-Result "Web deployment binds gunicorn to 8000" ($webDeployContent -match "0\.0\.0\.0:8000") "Gunicorn should bind to 0.0.0.0:8000"

# Healthcheck port consistency
$ingressYaml = Join-Path $RootPath "helm-statuspage/templates/ingress.yaml"
$ingressContent = if (Test-Path $ingressYaml) { Get-Content $ingressYaml -Raw } else { "" }
Test-Result "Ingress healthcheck port matches container (8000)" ($ingressContent -match "healthcheck-port.*8000") "Healthcheck port should be 8000"

# Namespace consistency across workflows
$cdContent = if (Test-Path $cdDeploy) { Get-Content $cdDeploy -Raw } else { "" }
$gsContent = if (Test-Path $gitopsSync) { Get-Content $gitopsSync -Raw } else { "" }

if ($cdContent -match 'HELM_NAMESPACE:\s*(\S+)') { $cdNs = $Matches[1] } else { $cdNs = "" }
if ($gsContent -match 'HELM_NAMESPACE:\s*(\S+)') { $gsNs = $Matches[1] } else { $gsNs = "" }
Test-Result "Namespace consistent: cd-deploy=$cdNs, gitops-sync=$gsNs" ($cdNs -eq $gsNs -and $cdNs.Length -gt 0) "Namespace mismatch between workflows"

# Cluster name consistency
if ($cdContent -match 'EKS_CLUSTER_NAME:\s*(\S+)') { $cdCluster = $Matches[1] } else { $cdCluster = "" }
if ($gsContent -match 'EKS_CLUSTER_NAME:\s*(\S+)') { $gsCluster = $Matches[1] } else { $gsCluster = "" }
Test-Result "Cluster name consistent across workflows" ($cdCluster -eq $gsCluster -and $cdCluster.Length -gt 0) "cd=$cdCluster, gitops=$gsCluster"

# Helm release name consistency
if ($cdContent -match 'HELM_RELEASE_NAME:\s*(\S+)') { $cdRelease = $Matches[1] } else { $cdRelease = "" }
if ($gsContent -match 'HELM_RELEASE_NAME:\s*(\S+)') { $gsRelease = $Matches[1] } else { $gsRelease = "" }
Test-Result "Helm release name consistent across workflows" ($cdRelease -eq $gsRelease -and $cdRelease.Length -gt 0) "cd=$cdRelease, gitops=$gsRelease"

# ============================================================================
# TEST GROUP 8: SECURITY CHECKS
# ============================================================================
Write-Section "8. SECURITY CHECKS"

# No hardcoded secrets in any file
$allFiles = Get-ChildItem -Path $RootPath -Include "*.yaml","*.yml","*.tf","*.ps1","*.sh","*.md" -Recurse -File
$secretPatterns = @(
    @{ Name = "AWS Access Key"; Pattern = "AKIA[A-Z0-9]{16}" },
    @{ Name = "AWS Secret Key"; Pattern = "[A-Za-z0-9/+=]{40}" },
    @{ Name = "Generic Password"; Pattern = "password\s*[:=]\s*['""][^'""]{8,}['""]" }
)

# Check no hardcoded AWS keys
$foundKey = $false
foreach ($f in $allFiles) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -match "AKIA[A-Z0-9]{16}") {
        $foundKey = $true
        break
    }
}
Test-Result "No hardcoded AWS access keys in codebase" (-not $foundKey) "Found AKIA key pattern in files!"

# Secrets use AWS Secrets Manager (not plaintext)
$secretsTf = Join-Path $RootPath "Terraform/modules/secrets.tf"
if (Test-Path $secretsTf) {
    $secretsContent = Get-Content $secretsTf -Raw
    Test-Result "Secrets use random_password (not hardcoded)" ($secretsContent -match "random_password") "Should use random_password for secrets"
    Test-Result "Secrets stored in AWS Secrets Manager" ($secretsContent -match "aws_secretsmanager_secret") "Should store secrets in Secrets Manager"
}

# ExternalSecret uses ClusterSecretStore
$esYaml = Join-Path $RootPath "helm-statuspage/templates/externalsecret.yaml"
if (Test-Path $esYaml) {
    $esContent = Get-Content $esYaml -Raw
    Test-Result "ExternalSecret refs ClusterSecretStore" ($esContent -match "kind:\s*ClusterSecretStore") "Should reference ClusterSecretStore"
}

# OIDC - no static credentials in workflows
foreach ($wf in (Get-ChildItem -Path $workflowDir -Filter "*.yml" -File -ErrorAction SilentlyContinue)) {
    $wfContent = Get-Content $wf.FullName -Raw
    $hasStaticKey = $wfContent -match "aws-access-key-id:" -and $wfContent -match "aws-secret-access-key:"
    Test-Result "Workflow $($wf.Name): no static AWS credentials" (-not $hasStaticKey) "Uses static credentials instead of OIDC"
}

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
Write-Section "TEST RESULTS SUMMARY"

Write-Host ""
Write-Host "  Total Tests:   $totalTests" -ForegroundColor White
Write-Host "  Passed:        $passedTests" -ForegroundColor Green
Write-Host "  Failed:        $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped:       $skippedTests" -ForegroundColor $(if ($skippedTests -gt 0) { "Yellow" } else { "Green" })

$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / ($totalTests - $skippedTests)) * 100, 1) } else { 0 }
Write-Host "  Pass Rate:     $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })

if ($failures.Count -gt 0) {
    Write-Host "`n  FAILURES:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host "    - $f" -ForegroundColor Red
    }
}

Write-Host ""
if ($failedTests -gt 0) {
    Write-Host "  [RESULT] $failedTests test(s) FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  [RESULT] All tests PASSED" -ForegroundColor Green
    exit 0
}
