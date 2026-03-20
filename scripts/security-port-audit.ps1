#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Security Port Audit - Scans all infrastructure code for port usage and security risks.
.DESCRIPTION
    Analyzes Terraform, Helm, and workflow files to:
    1. Map all ports used across the project
    2. Identify CIDR blocks and network rules
    3. Alert on dangerous configurations (0.0.0.0/0, open egress, etc.)
.EXAMPLE
    .\scripts\security-port-audit.ps1
#>

param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Continue"
$warnings = @()
$ports = @()
$cidrs = @()

function Write-Section($title) {
    Write-Host "`n$('=' * 70)" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
}

function Write-Finding($type, $file, $line, $detail) {
    $relPath = $file.Replace($RootPath, "").TrimStart("\", "/")
    switch ($type) {
        "ALERT"   { Write-Host "  [ALERT]   " -ForegroundColor Red -NoNewline }
        "WARNING" { Write-Host "  [WARNING] " -ForegroundColor Yellow -NoNewline }
        "INFO"    { Write-Host "  [INFO]    " -ForegroundColor Green -NoNewline }
    }
    Write-Host "$relPath" -ForegroundColor White -NoNewline
    if ($line -gt 0) { Write-Host ":$line" -ForegroundColor DarkGray -NoNewline }
    Write-Host " - $detail"
}

# ============================================================================
# SCAN TERRAFORM FILES
# ============================================================================
Write-Section "SCANNING TERRAFORM FILES"

$tfFiles = Get-ChildItem -Path $RootPath -Filter "*.tf" -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.terraform[\\/]' }
foreach ($tf in $tfFiles) {
    $content = Get-Content $tf.FullName -Raw
    $lines = Get-Content $tf.FullName

    # Find port references
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Match from_port, to_port, port = NNNN
        if ($line -match '(from_port|to_port|port)\s*=\s*(\d+)') {
            $port = $Matches[2]
            $ports += [PSCustomObject]@{
                Port   = [int]$port
                File   = $tf.FullName
                Line   = $i + 1
                Source  = "Terraform"
                Context = $line.Trim()
            }
        }
        # Match CIDR blocks
        if ($line -match 'cidr_blocks\s*=\s*\["([^"]+)"') {
            $cidr = $Matches[1]
            $cidrs += [PSCustomObject]@{
                CIDR    = $cidr
                File    = $tf.FullName
                Line    = $i + 1
                Source  = "Terraform"
                Context = $line.Trim()
            }
            if ($cidr -eq "0.0.0.0/0") {
                # Determine if it's ingress or egress by looking back
                $ruleType = "unknown"
                for ($j = $i; $j -ge [Math]::Max(0, $i - 10); $j--) {
                    if ($lines[$j] -match '^\s*(ingress|egress)\s*\{') {
                        $ruleType = $Matches[1]
                        break
                    }
                }
                # Find the security group name
                $sgName = "unknown"
                for ($j = $i; $j -ge 0; $j--) {
                    if ($lines[$j] -match 'resource\s+"aws_security_group"\s+"(\w+)"') {
                        $sgName = $Matches[1]
                        break
                    }
                }
                # Find the port range
                $fromPort = "any"; $toPort = "any"
                for ($j = [Math]::Max(0, $i - 8); $j -lt $i; $j++) {
                    if ($lines[$j] -match 'from_port\s*=\s*(\d+)') { $fromPort = $Matches[1] }
                    if ($lines[$j] -match 'to_port\s*=\s*(\d+)') { $toPort = $Matches[1] }
                }

                if ($ruleType -eq "ingress") {
                    $warnings += [PSCustomObject]@{
                        Level   = "ALERT"
                        File    = $tf.FullName
                        Line    = $i + 1
                        Detail  = "INGRESS from 0.0.0.0/0 on port(s) $fromPort-$toPort in SG '$sgName' - OPEN TO THE INTERNET!"
                    }
                    Write-Finding "ALERT" $tf.FullName ($i + 1) "INGRESS from 0.0.0.0/0 on port(s) $fromPort-$toPort in SG '$sgName'"
                } elseif ($ruleType -eq "egress") {
                    if ($fromPort -eq "0" -and $toPort -eq "0") {
                        Write-Finding "WARNING" $tf.FullName ($i + 1) "EGRESS to 0.0.0.0/0 (all ports) in SG '$sgName'"
                        $warnings += [PSCustomObject]@{
                            Level   = "WARNING"
                            File    = $tf.FullName
                            Line    = $i + 1
                            Detail  = "EGRESS to 0.0.0.0/0 (all ports) in SG '$sgName'"
                        }
                    }
                }
            }
        }

        # Check for public endpoint access
        if ($line -match 'cluster_endpoint_public_access\s*=\s*true') {
            Write-Finding "WARNING" $tf.FullName ($i + 1) "EKS cluster endpoint is PUBLIC - consider restricting access"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $tf.FullName
                Line    = $i + 1
                Detail  = "EKS cluster endpoint is publicly accessible"
            }
        }

        # Check for skip_final_snapshot
        if ($line -match 'skip_final_snapshot\s*=\s*true') {
            Write-Finding "WARNING" $tf.FullName ($i + 1) "RDS skip_final_snapshot=true - data loss risk on deletion"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $tf.FullName
                Line    = $i + 1
                Detail  = "RDS skip_final_snapshot=true"
            }
        }

        # Check for deletion_protection disabled
        if ($line -match 'deletion_protection\s*=\s*false') {
            Write-Finding "WARNING" $tf.FullName ($i + 1) "Deletion protection is DISABLED"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $tf.FullName
                Line    = $i + 1
                Detail  = "Deletion protection disabled"
            }
        }
    }
}

# ============================================================================
# SCAN HELM CHART FILES
# ============================================================================
Write-Section "SCANNING HELM CHART FILES"

$helmFiles = Get-ChildItem -Path "$RootPath\helm-statuspage" -Filter "*.yaml" -Recurse -File
$helmFiles += Get-ChildItem -Path "$RootPath\helm-statuspage" -Filter "*.yml" -Recurse -File
$helmFiles += Get-ChildItem -Path "$RootPath\helm-statuspage" -Filter "*.tpl" -Recurse -File

foreach ($hf in $helmFiles) {
    $lines = Get-Content $hf.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # containerPort, port, targetPort
        if ($line -match '(containerPort|targetPort|port):\s*(\d+)') {
            $port = $Matches[2]
            $ports += [PSCustomObject]@{
                Port    = [int]$port
                File    = $hf.FullName
                Line    = $i + 1
                Source  = "Helm"
                Context = $line.Trim()
            }
        }

        # healthcheck-port
        if ($line -match 'healthcheck-port.*?[''"](\d+)[''"]') {
            $port = $Matches[1]
            $ports += [PSCustomObject]@{
                Port    = [int]$port
                File    = $hf.FullName
                Line    = $i + 1
                Source  = "Helm"
                Context = $line.Trim()
            }
        }

        # Bind on 0.0.0.0
        if ($line -match '0\.0\.0\.0:(\d+)') {
            $port = $Matches[1]
            $ports += [PSCustomObject]@{
                Port    = [int]$port
                File    = $hf.FullName
                Line    = $i + 1
                Source  = "Helm"
                Context = $line.Trim()
            }
            Write-Finding "INFO" $hf.FullName ($i + 1) "Binding to 0.0.0.0:$port (all interfaces inside pod - expected for container)"
        }

        # internet-facing scheme
        if ($line -match 'scheme.*internet-facing') {
            Write-Finding "WARNING" $hf.FullName ($i + 1) "ALB scheme is internet-facing (public)"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $hf.FullName
                Line    = $i + 1
                Detail  = "ALB scheme is internet-facing"
            }
        }

        # ALLOWED_HOSTS = *
        if ($line -match 'allowedHosts.*"\*"') {
            Write-Finding "WARNING" $hf.FullName ($i + 1) "Django ALLOWED_HOSTS='*' - should be restricted in production"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $hf.FullName
                Line    = $i + 1
                Detail  = "Django ALLOWED_HOSTS is wildcard"
            }
        }
    }
}

# ============================================================================
# SCAN WORKFLOW FILES
# ============================================================================
Write-Section "SCANNING CI/CD WORKFLOW FILES"

$workflowDir = "$RootPath\.github\workflows"
if (Test-Path $workflowDir) {
    $wfFiles = Get-ChildItem -Path $workflowDir -Filter "*.yml" -File
    foreach ($wf in $wfFiles) {
        $lines = Get-Content $wf.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match 'id-token:\s*write') {
                Write-Finding "INFO" $wf.FullName ($i + 1) "Uses OIDC id-token (secure, no static credentials)"
            }
            if ($line -match 'secrets\.\w+') {
                Write-Finding "INFO" $wf.FullName ($i + 1) "References GitHub Secret: $($Matches[0])"
            }
        }
    }
} else {
    Write-Host "  No .github/workflows/ directory found." -ForegroundColor DarkGray
}

# ============================================================================
# SCAN CONFIGMAP FOR EXPOSED DATA
# ============================================================================
Write-Section "SCANNING CONFIGMAPS FOR SENSITIVE DATA"

$configFiles = Get-ChildItem -Path $RootPath -Filter "configmap.tf" -Recurse -File
foreach ($cf in $configFiles) {
    $lines = Get-Content $cf.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '(DB_HOST|REDIS_HOST)\s*=') {
            Write-Finding "INFO" $cf.FullName ($i + 1) "Database/Cache endpoint exposed in ConfigMap: $($line.Trim())"
        }
        if ($line -match 'ALLOWED_HOSTS\s*=\s*"\*"') {
            Write-Finding "WARNING" $cf.FullName ($i + 1) "ALLOWED_HOSTS='*' in ConfigMap - restrict in production"
            $warnings += [PSCustomObject]@{
                Level   = "WARNING"
                File    = $cf.FullName
                Line    = $i + 1
                Detail  = "ALLOWED_HOSTS wildcard in ConfigMap"
            }
        }
    }
}

# ============================================================================
# PORT SUMMARY TABLE
# ============================================================================
Write-Section "PORT INVENTORY (All Ports Found)"

$uniquePorts = $ports | Sort-Object Port -Unique | Select-Object Port -Unique

$portDescriptions = @{
    80   = "HTTP (ALB/Service)"
    443  = "HTTPS (ALB)"
    5432 = "PostgreSQL (RDS)"
    6379 = "Redis (ElastiCache)"
    8000 = "Gunicorn (Django App)"
    3100 = "Loki (Log Aggregation)"
}

Write-Host ""
Write-Host "  PORT    | DESCRIPTION               | FOUND IN" -ForegroundColor White
Write-Host "  --------+---------------------------+----------------------------------"
foreach ($up in ($ports | Sort-Object Port | Group-Object Port)) {
    $portNum = $up.Name
    $desc = if ($portDescriptions.ContainsKey([int]$portNum)) { $portDescriptions[[int]$portNum] } else { "Unknown" }
    $sources = ($up.Group | ForEach-Object { $_.Source } | Sort-Object -Unique) -join ", "
    $files = ($up.Group | ForEach-Object {
        $_.File.Replace($RootPath, "").TrimStart("\", "/")
    } | Sort-Object -Unique) -join ", "
    Write-Host ("  {0,-7} | {1,-25} | {2}" -f $portNum, $desc, $files)
}

# ============================================================================
# CIDR BLOCK SUMMARY
# ============================================================================
Write-Section "CIDR BLOCK INVENTORY"

Write-Host ""
foreach ($c in ($cidrs | Sort-Object CIDR)) {
    $relPath = $c.File.Replace($RootPath, "").TrimStart("\", "/")
    $status = if ($c.CIDR -eq "0.0.0.0/0") { "[OPEN]" } else { "[OK]  " }
    $color = if ($c.CIDR -eq "0.0.0.0/0") { "Red" } else { "Green" }
    Write-Host "  $status " -ForegroundColor $color -NoNewline
    Write-Host "$($c.CIDR) " -ForegroundColor White -NoNewline
    Write-Host "($relPath`:$($c.Line))" -ForegroundColor DarkGray
}

# ============================================================================
# SECURITY ALERTS SUMMARY
# ============================================================================
Write-Section "SECURITY SUMMARY"

$alerts = $warnings | Where-Object { $_.Level -eq "ALERT" }
$warningsList = $warnings | Where-Object { $_.Level -eq "WARNING" }

Write-Host ""
if ($alerts.Count -gt 0) {
    Write-Host "  CRITICAL ALERTS: $($alerts.Count)" -ForegroundColor Red
    foreach ($a in $alerts) {
        $relPath = $a.File.Replace($RootPath, "").TrimStart("\", "/")
        Write-Host "    [!] $($a.Detail)" -ForegroundColor Red
        Write-Host "        -> $relPath`:$($a.Line)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  CRITICAL ALERTS: 0" -ForegroundColor Green
}

Write-Host ""
if ($warningsList.Count -gt 0) {
    Write-Host "  WARNINGS: $($warningsList.Count)" -ForegroundColor Yellow
    foreach ($w in $warningsList) {
        $relPath = $w.File.Replace($RootPath, "").TrimStart("\", "/")
        Write-Host "    [~] $($w.Detail)" -ForegroundColor Yellow
        Write-Host "        -> $relPath`:$($w.Line)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNINGS: 0" -ForegroundColor Green
}

Write-Host ""
$totalPorts = ($ports | Sort-Object Port | Group-Object Port).Count
Write-Host "  Total unique ports: $totalPorts" -ForegroundColor White
Write-Host "  Total CIDR rules:   $($cidrs.Count)" -ForegroundColor White
Write-Host "  Alerts:             $($alerts.Count)" -ForegroundColor $(if ($alerts.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings:           $($warningsList.Count)" -ForegroundColor $(if ($warningsList.Count -gt 0) { "Yellow" } else { "Green" })

# Exit with non-zero if alerts found
if ($alerts.Count -gt 0) {
    Write-Host "`n  [RESULT] SECURITY ISSUES DETECTED - Review alerts above!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n  [RESULT] No critical security issues found." -ForegroundColor Green
    exit 0
}
