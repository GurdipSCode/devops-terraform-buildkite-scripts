# scripts/Invoke-OvermindAnalysis.ps1
<#
.SYNOPSIS
    Analyzes Terraform plan using Overmind

.DESCRIPTION
    Uses Overmind to analyze Terraform plan JSON for infrastructure changes,
    dependencies, blast radius, and risk assessment.

.PARAMETER PlanJsonPath
    Path to the Terraform plan JSON file

.PARAMETER OutputPath
    Optional path to save the analysis results

.PARAMETER Format
    Output format (json, text, markdown). Default: text

.PARAMETER IncludeBlastRadius
    Include blast radius analysis

.EXAMPLE
    .\scripts\Invoke-OvermindAnalysis.ps1 -PlanJsonPath "tfplan-dev.json"

.EXAMPLE
    .\scripts\Invoke-OvermindAnalysis.ps1 -PlanJsonPath "tfplan-prd.json" -OutputPath "overmind-analysis-prd.txt" -IncludeBlastRadius

.NOTES
    Requires Overmind CLI to be installed
    Install: https://overmind.tech/docs/installation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$PlanJsonPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("json", "text", "markdown")]
    [string]$Format = "text",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeBlastRadius
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Overmind Infrastructure Analysis"
Write-Host "═══════════════════════════════════════════════════════════════"

# Check if Overmind is installed
if (-not (Get-Command overmind -ErrorAction SilentlyContinue)) {
    Write-Warning "Overmind is not installed or not in PATH"
    Write-Host ""
    Write-Host "To install Overmind:"
    Write-Host "  Visit: https://overmind.tech/docs/installation"
    Write-Host ""
    Write-Host "Or using Homebrew (macOS/Linux):"
    Write-Host "  brew install overmindtech/tap/overmind-cli"
    Write-Host ""
    Write-Host "Skipping Overmind analysis..."
    exit 0  # Exit gracefully, not as error
}

Write-Host "✓ Overmind is installed"
Write-Host ""

# Verify plan JSON file exists and is valid JSON
if ((Get-Item $PlanJsonPath).Length -eq 0) {
    Write-Warning "Plan JSON file is empty: $PlanJsonPath"
    Write-Host "Skipping Overmind analysis..."
    exit 0
}

# Validate JSON
try {
    $planContent = Get-Content $PlanJsonPath -Raw | ConvertFrom-Json
    if (-not $planContent) {
        throw "Invalid JSON content"
    }
} catch {
    Write-Warning "Plan JSON file is not valid JSON: $PlanJsonPath"
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Skipping Overmind analysis..."
    exit 0
}

Write-Host "Analyzing plan: $PlanJsonPath"
Write-Host "Output format: $Format"
Write-Host ""

try {
    $analysisStart = Get-Date
    
    # Build Overmind command
    $overmindArgs = @(
        "terraform-plan",
        "analyze",
        $PlanJsonPath
    )
    
    if ($Format) {
        $overmindArgs += "--format"
        $overmindArgs += $Format
    }
    
    if ($IncludeBlastRadius) {
        $overmindArgs += "--blast-radius"
    }
    
    # Run Overmind analysis
    Write-Host "--- Running Overmind Analysis"
    Write-Host "Command: overmind $($overmindArgs -join ' ')"
    Write-Host ""
    
    if ($OutputPath) {
        # Save to file and display
        & overmind $overmindArgs | Tee-Object -FilePath $OutputPath
        Write-Host ""
        Write-Host "✓ Analysis saved to: $OutputPath"
    } else {
        # Display only
        & overmind $overmindArgs
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Overmind analysis failed with exit code: $LASTEXITCODE"
    }
    
    $analysisDuration = (Get-Date) - $analysisStart
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════"
    Write-Host "✓ Overmind analysis completed in $($analysisDuration.TotalSeconds) seconds"
    Write-Host "═══════════════════════════════════════════════════════════════"
    
} catch {
    Write-Warning "Overmind analysis failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "This is non-blocking. Continuing..."
    exit 0  # Exit gracefully, not as error
}

# Parse analysis for risk indicators
if ($OutputPath -and (Test-Path $OutputPath)) {
    $analysisContent = Get-Content $OutputPath -Raw
    
    # Look for risk indicators
    $riskKeywords = @(
        "high risk",
        "critical change",
        "large blast radius",
        "destructive",
        "data loss",
        "service disruption"
    )
    
    $foundRisk = $false
    $foundKeywords = @()
    
    foreach ($keyword in $riskKeywords) {
        if ($analysisContent -match $keyword) {
            $foundRisk = $true
            $foundKeywords += $keyword
        }
    }
    
    if ($foundRisk) {
        Write-Host ""
        Write-Host "⚠️  ATTENTION: Overmind detected potential risks"
        Write-Host "Risk indicators found: $($foundKeywords -join ', ')"
        Write-Host "Review the analysis above carefully before proceeding"
        Write-Host ""
        
        # Create Buildkite annotation if available
        if (Get-Command buildkite-agent -ErrorAction SilentlyContinue) {
            $annotation = @"
:warning: **Overmind Risk Detection**

Potential risks identified in Terraform plan:
$($foundKeywords | ForEach-Object { "- $_" } | Out-String)

Review the Overmind analysis in build artifacts before applying.
"@
            buildkite-agent annotate --style warning --context "overmind-risk" $annotation
        }
    } else {
        Write-Host ""
        Write-Host "✓ No high-risk changes detected"
        Write-Host ""
    }
}

# Generate summary statistics if JSON format
if ($Format -eq "json" -and $OutputPath -and (Test-Path $OutputPath)) {
    try {
        $analysis = Get-Content $OutputPath -Raw | ConvertFrom-Json
        
        Write-Host ""
        Write-Host "--- Analysis Summary"
        
        if ($analysis.changes) {
            Write-Host "Total changes: $($analysis.changes.Count)"
        }
        
        if ($analysis.risk_score) {
            Write-Host "Risk score: $($analysis.risk_score)"
        }
        
        if ($analysis.blast_radius) {
            Write-Host "Blast radius: $($analysis.blast_radius.affected_resources) resources"
        }
        
    } catch {
        # Ignore JSON parsing errors for summary
    }
}
