#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs comprehensive security scans on Terraform code
.DESCRIPTION
    Executes multiple security scanning tools:
    - Checkov: 1000+ security and compliance checks
    - tfsec: Terraform-specific security scanner
    - KICS: Keeping Infrastructure as Code Secure
    - Semgrep: Lightweight static analysis
    - Mondoo: Policy-as-code security scanning
.PARAMETER OutputDir
    Directory to save scan results (default: scan-results)
.PARAMETER FailOnHigh
    Exit with error code if high severity issues found (default: false)
.EXAMPLE
    .\run-security-scans.ps1
    .\run-security-scans.ps1 -OutputDir "security-reports" -FailOnHigh
#>

param(
    [string]$OutputDir = "scan-results",
    [switch]$FailOnHigh
)

$ErrorActionPreference = "Continue"  # Continue on scan failures to run all scanners

Write-Host "========================================"
Write-Host "🛡️  Comprehensive Security Scanning"
Write-Host "========================================"
Write-Host ""

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Track results
$scanResults = @{
    Checkov = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
    Tfsec = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
    KICS = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
    Semgrep = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
    Mondoo = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
    GitGuardian = @{ Status = "skipped"; High = 0; Medium = 0; Low = 0 }
}

$totalHigh = 0
$totalMedium = 0
$totalLow = 0

# ============================================
# CHECKOV
# ============================================
Write-Host "--- 🔍 Running Checkov"

if (Get-Command "checkov" -ErrorAction SilentlyContinue) {
    try {
        $checkovOutput = "$OutputDir/checkov-results.json"
        $checkovSarif = "$OutputDir/checkov-results.sarif"
        
        # Run Checkov with JSON and SARIF output
        checkov --directory . `
            --output json `
            --output-file-path $OutputDir `
            --framework terraform `
            --compact `
            --quiet 2>&1 | Out-Null
        
        # Rename output file
        if (Test-Path "$OutputDir/results_json.json") {
            Move-Item "$OutputDir/results_json.json" $checkovOutput -Force
        }
        
        # Parse results
        if (Test-Path $checkovOutput) {
            $checkovData = Get-Content $checkovOutput | ConvertFrom-Json
            
            $passed = 0
            $failed = 0
            $skipped = 0
            
            foreach ($check in $checkovData.results) {
                if ($check.passed_checks) { $passed += $check.passed_checks.Count }
                if ($check.failed_checks) { $failed += $check.failed_checks.Count }
                if ($check.skipped_checks) { $skipped += $check.skipped_checks.Count }
            }
            
            # Count by severity (Checkov uses check IDs for severity)
            $highCount = ($checkovData.results.failed_checks | Where-Object { $_.severity -eq "HIGH" -or $_.severity -eq "CRITICAL" }).Count
            $mediumCount = ($checkovData.results.failed_checks | Where-Object { $_.severity -eq "MEDIUM" }).Count
            $lowCount = ($checkovData.results.failed_checks | Where-Object { $_.severity -eq "LOW" -or $_.severity -eq "INFO" }).Count
            
            $scanResults.Checkov = @{
                Status = "completed"
                High = $highCount
                Medium = $mediumCount
                Low = $failed - $highCount - $mediumCount
                Passed = $passed
                Failed = $failed
            }
            
            Write-Host "  ✓ Checkov completed" -ForegroundColor Green
            Write-Host "    Passed: $passed | Failed: $failed | Skipped: $skipped"
            Write-Host "    Results: $checkovOutput"
        }
    }
    catch {
        Write-Host "  ⚠ Checkov error: $_" -ForegroundColor Yellow
        $scanResults.Checkov.Status = "error"
    }
}
else {
    Write-Host "  ⚠ Checkov not installed (pip install checkov)" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# TFSEC
# ============================================
Write-Host "--- 🔍 Running tfsec"

if (Get-Command "tfsec" -ErrorAction SilentlyContinue) {
    try {
        $tfsecOutput = "$OutputDir/tfsec-results.json"
        $tfsecSarif = "$OutputDir/tfsec-results.sarif"
        
        # Run tfsec with JSON output
        tfsec . --format json --out $tfsecOutput 2>&1 | Out-Null
        
        # Also generate SARIF for GitHub integration
        tfsec . --format sarif --out $tfsecSarif 2>&1 | Out-Null
        
        if (Test-Path $tfsecOutput) {
            $tfsecData = Get-Content $tfsecOutput | ConvertFrom-Json
            
            $highCount = ($tfsecData.results | Where-Object { $_.severity -eq "HIGH" -or $_.severity -eq "CRITICAL" }).Count
            $mediumCount = ($tfsecData.results | Where-Object { $_.severity -eq "MEDIUM" }).Count
            $lowCount = ($tfsecData.results | Where-Object { $_.severity -eq "LOW" }).Count
            
            $scanResults.Tfsec = @{
                Status = "completed"
                High = $highCount
                Medium = $mediumCount
                Low = $lowCount
                Total = $tfsecData.results.Count
            }
            
            Write-Host "  ✓ tfsec completed" -ForegroundColor Green
            Write-Host "    Issues: $($tfsecData.results.Count) (High: $highCount, Medium: $mediumCount, Low: $lowCount)"
            Write-Host "    Results: $tfsecOutput"
        }
    }
    catch {
        Write-Host "  ⚠ tfsec error: $_" -ForegroundColor Yellow
        $scanResults.Tfsec.Status = "error"
    }
}
else {
    Write-Host "  ⚠ tfsec not installed (choco install tfsec)" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# KICS (Keeping Infrastructure as Code Secure)
# ============================================
Write-Host "--- 🔍 Running KICS"

if (Get-Command "kics" -ErrorAction SilentlyContinue) {
    try {
        $kicsOutput = "$OutputDir/kics-results.json"
        $kicsSarif = "$OutputDir/kics-results.sarif"
        $kicsHtml = "$OutputDir/kics-results.html"
        
        # Run KICS scan
        kics scan `
            --path . `
            --output-path $OutputDir `
            --output-name kics-results `
            --report-formats "json,sarif,html" `
            --type terraform `
            --no-progress `
            --ci 2>&1 | Out-Null
        
        if (Test-Path $kicsOutput) {
            $kicsData = Get-Content $kicsOutput | ConvertFrom-Json
            
            $highCount = $kicsData.severity_counters.HIGH
            $mediumCount = $kicsData.severity_counters.MEDIUM
            $lowCount = $kicsData.severity_counters.LOW + $kicsData.severity_counters.INFO
            
            $scanResults.KICS = @{
                Status = "completed"
                High = $highCount
                Medium = $mediumCount
                Low = $lowCount
                Total = $kicsData.total_counter
                FilesScanned = $kicsData.files_scanned
            }
            
            Write-Host "  ✓ KICS completed" -ForegroundColor Green
            Write-Host "    Issues: $($kicsData.total_counter) (High: $highCount, Medium: $mediumCount, Low: $lowCount)"
            Write-Host "    Files scanned: $($kicsData.files_scanned)"
            Write-Host "    Results: $kicsOutput"
            Write-Host "    HTML Report: $kicsHtml"
        }
    }
    catch {
        Write-Host "  ⚠ KICS error: $_" -ForegroundColor Yellow
        $scanResults.KICS.Status = "error"
    }
}
else {
    Write-Host "  ⚠ KICS not installed" -ForegroundColor Yellow
    Write-Host "    Install: choco install kics" -ForegroundColor Yellow
    Write-Host "    Or: docker pull checkmarx/kics:latest" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# SEMGREP
# ============================================
Write-Host "--- 🔍 Running Semgrep"

if (Get-Command "semgrep" -ErrorAction SilentlyContinue) {
    try {
        $semgrepOutput = "$OutputDir/semgrep-results.json"
        $semgrepSarif = "$OutputDir/semgrep-results.sarif"
        
        # Run Semgrep with Terraform rules
        # Using p/terraform and p/security-audit rulesets
        semgrep scan `
            --config "p/terraform" `
            --config "p/security-audit" `
            --json `
            --output $semgrepOutput `
            --quiet `
            . 2>&1 | Out-Null
        
        # Also generate SARIF
        semgrep scan `
            --config "p/terraform" `
            --config "p/security-audit" `
            --sarif `
            --output $semgrepSarif `
            --quiet `
            . 2>&1 | Out-Null
        
        if (Test-Path $semgrepOutput) {
            $semgrepData = Get-Content $semgrepOutput | ConvertFrom-Json
            
            $highCount = ($semgrepData.results | Where-Object { 
                $_.extra.severity -eq "ERROR" -or $_.extra.metadata.confidence -eq "HIGH" 
            }).Count
            $mediumCount = ($semgrepData.results | Where-Object { 
                $_.extra.severity -eq "WARNING" 
            }).Count
            $lowCount = ($semgrepData.results | Where-Object { 
                $_.extra.severity -eq "INFO" 
            }).Count
            
            $scanResults.Semgrep = @{
                Status = "completed"
                High = $highCount
                Medium = $mediumCount
                Low = $lowCount
                Total = $semgrepData.results.Count
                Errors = $semgrepData.errors.Count
            }
            
            Write-Host "  ✓ Semgrep completed" -ForegroundColor Green
            Write-Host "    Findings: $($semgrepData.results.Count) (High: $highCount, Medium: $mediumCount, Low: $lowCount)"
            Write-Host "    Results: $semgrepOutput"
        }
    }
    catch {
        Write-Host "  ⚠ Semgrep error: $_" -ForegroundColor Yellow
        $scanResults.Semgrep.Status = "error"
    }
}
else {
    Write-Host "  ⚠ Semgrep not installed" -ForegroundColor Yellow
    Write-Host "    Install: pip install semgrep" -ForegroundColor Yellow
    Write-Host "    Or: choco install semgrep" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# MONDOO
# ============================================
Write-Host "--- 🔍 Running Mondoo"

if (Get-Command "cnspec" -ErrorAction SilentlyContinue) {
    try {
        $mondooOutput = "$OutputDir/mondoo-results.json"
        $mondooYaml = "$OutputDir/mondoo-results.yaml"
        
        # Check if Mondoo is configured
        $mondooStatus = cnspec status 2>&1
        
        if ($LASTEXITCODE -eq 0 -or $env:MONDOO_CONFIG_PATH) {
            # Run Mondoo scan on Terraform files
            cnspec scan terraform . `
                --output json `
                --output-target $mondooOutput `
                2>&1 | Out-Null
            
            # Also get YAML output for readability
            cnspec scan terraform . `
                --output yaml `
                --output-target $mondooYaml `
                2>&1 | Out-Null
            
            if (Test-Path $mondooOutput) {
                $mondooData = Get-Content $mondooOutput | ConvertFrom-Json
                
                # Parse Mondoo results
                $highCount = 0
                $mediumCount = 0
                $lowCount = 0
                
                if ($mondooData.data) {
                    foreach ($finding in $mondooData.data) {
                        switch ($finding.severity) {
                            { $_ -ge 80 } { $highCount++ }
                            { $_ -ge 40 -and $_ -lt 80 } { $mediumCount++ }
                            { $_ -lt 40 } { $lowCount++ }
                        }
                    }
                }
                
                # Get score if available
                $score = $mondooData.score ?? "N/A"
                
                $scanResults.Mondoo = @{
                    Status = "completed"
                    High = $highCount
                    Medium = $mediumCount
                    Low = $lowCount
                    Score = $score
                }
                
                Write-Host "  ✓ Mondoo completed" -ForegroundColor Green
                Write-Host "    Score: $score"
                Write-Host "    Issues: High: $highCount, Medium: $mediumCount, Low: $lowCount"
                Write-Host "    Results: $mondooOutput"
            }
        }
        else {
            Write-Host "  ⚠ Mondoo not configured" -ForegroundColor Yellow
            Write-Host "    Run: cnspec login" -ForegroundColor Yellow
            
            # Try running without authentication (limited functionality)
            Write-Host "    Attempting unauthenticated scan..."
            cnspec scan terraform . `
                --output json `
                --output-target $mondooOutput `
                2>&1 | Out-Null
            
            if (Test-Path $mondooOutput) {
                Write-Host "  ✓ Mondoo scan completed (unauthenticated)" -ForegroundColor Green
                $scanResults.Mondoo.Status = "completed-limited"
            }
        }
    }
    catch {
        Write-Host "  ⚠ Mondoo error: $_" -ForegroundColor Yellow
        $scanResults.Mondoo.Status = "error"
    }
}
else {
    Write-Host "  ⚠ Mondoo (cnspec) not installed" -ForegroundColor Yellow
    Write-Host "    Install from: https://mondoo.com/docs/cnspec/" -ForegroundColor Yellow
    Write-Host "    Windows: choco install mondoo" -ForegroundColor Yellow
    Write-Host "    Or: Invoke-Expression (Invoke-WebRequest -Uri 'https://install.mondoo.com/ps1' -UseBasicParsing).Content" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# GITGUARDIAN (Secret Scanning)
# ============================================
Write-Host "--- 🔍 Running GitGuardian (Secret Scanning)"

if (Get-Command "ggshield" -ErrorAction SilentlyContinue) {
    try {
        $ggOutput = "$OutputDir/gitguardian-results.json"
        
        # Check if GitGuardian is configured
        if ($env:GITGUARDIAN_API_KEY) {
            # Run ggshield secret scan
            $ggResult = ggshield secret scan path . `
                --json `
                --output $ggOutput `
                --recursive `
                --show-secrets `
                2>&1
            
            $ggExitCode = $LASTEXITCODE
            
            if (Test-Path $ggOutput) {
                $ggData = Get-Content $ggOutput | ConvertFrom-Json
                
                # Count secrets found
                $secretsFound = 0
                $highCount = 0
                $mediumCount = 0
                $lowCount = 0
                
                if ($ggData.scans) {
                    foreach ($scan in $ggData.scans) {
                        if ($scan.incidents) {
                            $secretsFound += $scan.incidents.Count
                            foreach ($incident in $scan.incidents) {
                                # GitGuardian classifies by detector, we'll treat all as high
                                $highCount++
                            }
                        }
                    }
                }
                
                $scanResults.GitGuardian = @{
                    Status = "completed"
                    High = $highCount
                    Medium = $mediumCount
                    Low = $lowCount
                    SecretsFound = $secretsFound
                }
                
                if ($secretsFound -gt 0) {
                    Write-Host "  ⚠ GitGuardian completed - SECRETS FOUND!" -ForegroundColor Red
                    Write-Host "    Secrets detected: $secretsFound" -ForegroundColor Red
                }
                else {
                    Write-Host "  ✓ GitGuardian completed - No secrets found" -ForegroundColor Green
                }
                Write-Host "    Results: $ggOutput"
            }
            else {
                # No output file but scan completed
                if ($ggExitCode -eq 0) {
                    $scanResults.GitGuardian = @{
                        Status = "completed"
                        High = 0
                        Medium = 0
                        Low = 0
                        SecretsFound = 0
                    }
                    Write-Host "  ✓ GitGuardian completed - No secrets found" -ForegroundColor Green
                }
                else {
                    Write-Host "  ⚠ GitGuardian scan had issues" -ForegroundColor Yellow
                    $scanResults.GitGuardian.Status = "error"
                }
            }
        }
        else {
            Write-Host "  ⚠ GitGuardian API key not configured" -ForegroundColor Yellow
            Write-Host "    Set GITGUARDIAN_API_KEY environment variable" -ForegroundColor Yellow
            Write-Host "    Get your API key from: https://dashboard.gitguardian.com/api/personal-access-tokens" -ForegroundColor Yellow
            
            # Try running in offline mode if available
            Write-Host "    Attempting offline scan..."
            $ggResult = ggshield secret scan path . --json --output $ggOutput 2>&1
            
            if ($LASTEXITCODE -eq 0 -and (Test-Path $ggOutput)) {
                Write-Host "  ✓ GitGuardian offline scan completed" -ForegroundColor Green
                $scanResults.GitGuardian.Status = "completed-limited"
            }
        }
    }
    catch {
        Write-Host "  ⚠ GitGuardian error: $_" -ForegroundColor Yellow
        $scanResults.GitGuardian.Status = "error"
    }
}
else {
    Write-Host "  ⚠ GitGuardian (ggshield) not installed" -ForegroundColor Yellow
    Write-Host "    Install: pip install ggshield" -ForegroundColor Yellow
    Write-Host "    Or: pipx install ggshield" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================"
Write-Host "📊 Security Scan Summary"
Write-Host "========================================"
Write-Host ""

# Calculate totals
foreach ($scanner in $scanResults.Keys) {
    if ($scanResults[$scanner].Status -eq "completed" -or $scanResults[$scanner].Status -eq "completed-limited") {
        $totalHigh += $scanResults[$scanner].High
        $totalMedium += $scanResults[$scanner].Medium
        $totalLow += $scanResults[$scanner].Low
    }
}

# Display summary table
Write-Host "Scanner        Status          High    Medium    Low"
Write-Host "─────────────────────────────────────────────────────"

foreach ($scanner in @("Checkov", "Tfsec", "KICS", "Semgrep", "Mondoo", "GitGuardian")) {
    $result = $scanResults[$scanner]
    $status = $result.Status.PadRight(15)
    $high = "$($result.High)".PadLeft(4)
    $medium = "$($result.Medium)".PadLeft(6)
    $low = "$($result.Low)".PadLeft(6)
    
    $color = switch ($result.Status) {
        "completed" { "Green" }
        "completed-limited" { "Yellow" }
        "error" { "Red" }
        default { "Gray" }
    }
    
    Write-Host "$($scanner.PadRight(14)) " -NoNewline
    Write-Host "$status" -ForegroundColor $color -NoNewline
    
    if ($result.High -gt 0) {
        Write-Host "$high" -ForegroundColor Red -NoNewline
    } else {
        Write-Host "$high" -NoNewline
    }
    
    if ($result.Medium -gt 0) {
        Write-Host "$medium" -ForegroundColor Yellow -NoNewline
    } else {
        Write-Host "$medium" -NoNewline
    }
    
    Write-Host "$low"
}

Write-Host "─────────────────────────────────────────────────────"
Write-Host "TOTAL                      " -NoNewline

if ($totalHigh -gt 0) {
    Write-Host "$($totalHigh.ToString().PadLeft(4))" -ForegroundColor Red -NoNewline
} else {
    Write-Host "$($totalHigh.ToString().PadLeft(4))" -ForegroundColor Green -NoNewline
}

if ($totalMedium -gt 0) {
    Write-Host "$($totalMedium.ToString().PadLeft(6))" -ForegroundColor Yellow -NoNewline
} else {
    Write-Host "$($totalMedium.ToString().PadLeft(6))" -NoNewline
}

Write-Host "$($totalLow.ToString().PadLeft(6))"

Write-Host ""

# Create summary JSON
$summaryFile = "$OutputDir/security-scan-summary.json"
$summary = @{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    totals = @{
        high = $totalHigh
        medium = $totalMedium
        low = $totalLow
    }
    scanners = $scanResults
}

$summary | ConvertTo-Json -Depth 10 | Out-File $summaryFile -Encoding UTF8
Write-Host "Summary saved to: $summaryFile"

# Upload artifacts if in Buildkite
if (Get-Command "buildkite-agent" -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "--- 📤 Uploading scan results to Buildkite"
    buildkite-agent artifact upload "$OutputDir/*"
    
    # Create Buildkite annotation
    $annotationStyle = if ($totalHigh -gt 0) { "error" } elseif ($totalMedium -gt 0) { "warning" } else { "success" }
    
    $annotation = @"
## 🛡️ Security Scan Results

| Scanner | Status | High | Medium | Low |
|---------|--------|------|--------|-----|
| Checkov | $($scanResults.Checkov.Status) | $($scanResults.Checkov.High) | $($scanResults.Checkov.Medium) | $($scanResults.Checkov.Low) |
| tfsec | $($scanResults.Tfsec.Status) | $($scanResults.Tfsec.High) | $($scanResults.Tfsec.Medium) | $($scanResults.Tfsec.Low) |
| KICS | $($scanResults.KICS.Status) | $($scanResults.KICS.High) | $($scanResults.KICS.Medium) | $($scanResults.KICS.Low) |
| Semgrep | $($scanResults.Semgrep.Status) | $($scanResults.Semgrep.High) | $($scanResults.Semgrep.Medium) | $($scanResults.Semgrep.Low) |
| Mondoo | $($scanResults.Mondoo.Status) | $($scanResults.Mondoo.High) | $($scanResults.Mondoo.Medium) | $($scanResults.Mondoo.Low) |
| GitGuardian | $($scanResults.GitGuardian.Status) | $($scanResults.GitGuardian.High) | $($scanResults.GitGuardian.Medium) | $($scanResults.GitGuardian.Low) |
| **TOTAL** | | **$totalHigh** | **$totalMedium** | **$totalLow** |

"@
    
    if ($totalHigh -gt 0) {
        $annotation += "`n⚠️ **$totalHigh high severity issues found!** Review before deploying.`n"
    }
    
    $annotation | buildkite-agent annotate --style $annotationStyle --context "security-scans"
}

Write-Host ""
Write-Host "========================================"

# Exit code logic
if ($FailOnHigh -and $totalHigh -gt 0) {
    Write-Host "❌ FAILED: $totalHigh high severity issues found" -ForegroundColor Red
    Write-Host "========================================"
    exit 1
}
elseif ($totalHigh -gt 0) {
    Write-Host "⚠️  WARNING: $totalHigh high severity issues found" -ForegroundColor Yellow
    Write-Host "========================================"
    exit 0
}
else {
    Write-Host "✅ PASSED: No high severity issues" -ForegroundColor Green
    Write-Host "========================================"
    exit 0
}
