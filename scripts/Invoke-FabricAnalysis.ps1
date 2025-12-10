# scripts/Invoke-FabricAnalysis.ps1
<#
.SYNOPSIS
    Analyzes Terraform plan using Fabric AI

.DESCRIPTION
    Uses Fabric to analyze Terraform plan output for security issues,
    best practices, cost optimization, and general recommendations.

.PARAMETER PlanSummaryPath
    Path to the Terraform plan summary text file

.PARAMETER Pattern
    Fabric pattern to use (default: analyze_terraform_plan)

.PARAMETER OutputPath
    Optional path to save the analysis results

.EXAMPLE
    .\scripts\Invoke-FabricAnalysis.ps1 -PlanSummaryPath "plan-summary-dev.txt"

.EXAMPLE
    .\scripts\Invoke-FabricAnalysis.ps1 -PlanSummaryPath "plan-summary-prd.txt" -Pattern "analyze_terraform_plan" -OutputPath "fabric-analysis-prd.txt"

.NOTES
    Requires Fabric to be installed and available in PATH
    Install: pip install fabric-ai
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$PlanSummaryPath,
    
    [Parameter(Mandatory=$false)]
    [string]$Pattern = "analyze_terraform_plan",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Fabric AI Analysis"
Write-Host "═══════════════════════════════════════════════════════════════"

# Check if Fabric is installed
if (-not (Get-Command fabric -ErrorAction SilentlyContinue)) {
    Write-Warning "Fabric is not installed or not in PATH"
    Write-Host ""
    Write-Host "To install Fabric:"
    Write-Host "  pip install fabric-ai"
    Write-Host ""
    Write-Host "Or using pipx:"
    Write-Host "  pipx install fabric-ai"
    Write-Host ""
    Write-Host "Skipping Fabric analysis..."
    exit 0  # Exit gracefully, not as error
}

Write-Host "✓ Fabric is installed"
Write-Host ""

# Verify plan summary file exists and is not empty
if ((Get-Item $PlanSummaryPath).Length -eq 0) {
    Write-Warning "Plan summary file is empty: $PlanSummaryPath"
    Write-Host "Skipping Fabric analysis..."
    exit 0
}

Write-Host "Analyzing plan: $PlanSummaryPath"
Write-Host "Using pattern: $Pattern"
Write-Host ""

try {
    $analysisStart = Get-Date
    
    # Run Fabric analysis
    Write-Host "--- Running Fabric AI Analysis"
    
    if ($OutputPath) {
        # Save to file and display
        Get-Content $PlanSummaryPath | fabric --pattern $Pattern | Tee-Object -FilePath $OutputPath
        Write-Host ""
        Write-Host "✓ Analysis saved to: $OutputPath"
    } else {
        # Display only
        Get-Content $PlanSummaryPath | fabric --pattern $Pattern
    }
    
    $analysisDuration = (Get-Date) - $analysisStart
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════"
    Write-Host "✓ Fabric analysis completed in $($analysisDuration.TotalSeconds) seconds"
    Write-Host "═══════════════════════════════════════════════════════════════"
    
} catch {
    Write-Warning "Fabric analysis failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "This is non-blocking. Continuing..."
    exit 0  # Exit gracefully, not as error
}

# Check if analysis output contains critical issues
if ($OutputPath -and (Test-Path $OutputPath)) {
    $analysisContent = Get-Content $OutputPath -Raw
    
    # Look for critical keywords
    $criticalKeywords = @(
        "critical",
        "high severity",
        "security vulnerability",
        "exposed credentials",
        "publicly accessible"
    )
    
    $foundCritical = $false
    foreach ($keyword in $criticalKeywords) {
        if ($analysisContent -match $keyword) {
            $foundCritical = $true
            break
        }
    }
    
    if ($foundCritical) {
        Write-Host ""
        Write-Host "⚠️  ATTENTION: Fabric detected potential critical issues"
        Write-Host "Review the analysis above carefully before proceeding"
        Write-Host ""
    }
}
