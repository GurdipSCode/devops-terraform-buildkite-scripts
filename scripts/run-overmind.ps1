#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs Overmind CLI for blast radius and risk analysis
.DESCRIPTION
    Analyzes Terraform plan with Overmind to identify blast radius and potential risks
.PARAMETER PlanFile
    Path to the Terraform plan file (binary)
.PARAMETER Environment
    Environment name for context
.PARAMETER OutputDir
    Directory to save Overmind results (default: overmind-results)
.EXAMPLE
    .\run-overmind-analysis.ps1 -PlanFile "tfplan-dev" -Environment "dev"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PlanFile,
    
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    
    [string]$OutputDir = "overmind-results"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "🔍 Overmind Blast Radius Analysis"
Write-Host "========================================"
Write-Host "Environment: $Environment"
Write-Host "Plan File: $PlanFile"
Write-Host ""

# Check if Overmind CLI is installed
if (-not (Get-Command "overmind" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Error: Overmind CLI not found" -ForegroundColor Red
    Write-Host "Install it with:" -ForegroundColor Yellow
    Write-Host "  Windows: winget install Overmind.OvermindCLI" -ForegroundColor Yellow
    Write-Host "  macOS: brew install overmindtech/overmind/overmind-cli" -ForegroundColor Yellow
    Write-Host "  Or visit: https://docs.overmind.tech/cli/overview" -ForegroundColor Yellow
    exit 1
}

# Check if plan file exists
if (-not (Test-Path $PlanFile)) {
    Write-Host "❌ Error: Plan file not found: $PlanFile" -ForegroundColor Red
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Convert binary plan to JSON for Overmind
Write-Host "--- 📄 Converting plan to JSON"
$planJson = "$OutputDir/tfplan-$Environment.json"
try {
    terraform show -json $PlanFile | Out-File -FilePath $planJson -Encoding UTF8
    Write-Host "✓ Plan converted to JSON: $planJson" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error converting plan to JSON: $_" -ForegroundColor Red
    exit 1
}

# Submit plan to Overmind
Write-Host ""
Write-Host "--- 🚀 Submitting plan to Overmind"
try {
    # Check if we're authenticated to Overmind
    $authStatus = overmind auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Not authenticated to Overmind" -ForegroundColor Yellow
        
        # Check for API key in environment
        if ($env:OVM_API_KEY) {
            Write-Host "Authenticating with OVM_API_KEY..." -ForegroundColor Yellow
            # Overmind will use the API key from environment
        }
        else {
            Write-Host "❌ Error: No Overmind authentication found" -ForegroundColor Red
            Write-Host "Set OVM_API_KEY environment variable or run 'overmind auth'" -ForegroundColor Yellow
            exit 1
        }
    }
    else {
        Write-Host "✓ Authenticated to Overmind" -ForegroundColor Green
    }
    
    # Submit the plan
    Write-Host "Submitting plan for analysis..."
    $changeOutput = overmind changes submit-plan $planJson --title "Terraform $Environment deployment" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Error submitting plan to Overmind: $changeOutput" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Plan submitted successfully" -ForegroundColor Green
    
    # Extract change UUID from output
    $changeUuid = $changeOutput | Select-String -Pattern "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})" | ForEach-Object { $_.Matches[0].Value }
    
    if ($changeUuid) {
        Write-Host "Change UUID: $changeUuid"
        $changeUrl = "https://app.overmind.tech/changes/$changeUuid"
        Write-Host "View in browser: $changeUrl" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "❌ Error submitting to Overmind: $_" -ForegroundColor Red
    exit 1
}

# Wait for analysis to complete
Write-Host ""
Write-Host "--- ⏳ Waiting for blast radius calculation"
Start-Sleep -Seconds 5

# Get the change details
Write-Host ""
Write-Host "--- 📊 Retrieving analysis results"
try {
    # Get change as markdown
    $markdownOutput = "$OutputDir/overmind-analysis-$Environment.md"
    overmind changes get-change --format markdown --uuid $changeUuid | Out-File -FilePath $markdownOutput -Encoding UTF8
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Analysis saved to: $markdownOutput" -ForegroundColor Green
    }
    
    # Get change as JSON for programmatic access
    $jsonOutput = "$OutputDir/overmind-analysis-$Environment.json"
    overmind changes get-change --format json --uuid $changeUuid | Out-File -FilePath $jsonOutput -Encoding UTF8
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ JSON data saved to: $jsonOutput" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠ Warning: Could not retrieve full analysis: $_" -ForegroundColor Yellow
}

# Parse and display results
Write-Host ""
Write-Host "========================================"
Write-Host "📊 Overmind Analysis Summary"
Write-Host "========================================"
Write-Host ""

if (Test-Path $jsonOutput) {
    try {
        $analysis = Get-Content $jsonOutput | ConvertFrom-Json
        
        # Display blast radius stats
        if ($analysis.properties.blastRadius) {
            $blastRadius = $analysis.properties.blastRadius
            Write-Host "Blast Radius:"
            Write-Host "  Items affected: $($blastRadius.totalItems)" -ForegroundColor $(if ($blastRadius.totalItems -lt 10) { "Green" } elseif ($blastRadius.totalItems -lt 50) { "Yellow" } else { "Red" })
            Write-Host "  Edges (connections): $($blastRadius.totalEdges)"
        }
        
        # Display risk count
        if ($analysis.properties.risks) {
            $riskCount = ($analysis.properties.risks | Measure-Object).Count
            Write-Host ""
            Write-Host "Risks identified: $riskCount" -ForegroundColor $(if ($riskCount -eq 0) { "Green" } elseif ($riskCount -lt 5) { "Yellow" } else { "Red" })
            
            if ($riskCount -gt 0) {
                Write-Host ""
                Write-Host "Risk Summary:"
                foreach ($risk in $analysis.properties.risks) {
                    $severity = $risk.severity
                    $color = switch ($severity) {
                        "high" { "Red" }
                        "medium" { "Yellow" }
                        "low" { "Cyan" }
                        default { "White" }
                    }
                    Write-Host "  [$severity] $($risk.title)" -ForegroundColor $color
                }
            }
        }
        
        # Display planned changes
        if ($analysis.properties.plannedChanges) {
            $changes = $analysis.properties.plannedChanges
            Write-Host ""
            Write-Host "Planned Changes:"
            Write-Host "  Create: $($changes.created)" -ForegroundColor Green
            Write-Host "  Update: $($changes.updated)" -ForegroundColor Yellow
            Write-Host "  Delete: $($changes.deleted)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "⚠ Could not parse analysis JSON: $_" -ForegroundColor Yellow
    }
}

# Display markdown summary
if (Test-Path $markdownOutput) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "📝 Full Analysis Report"
    Write-Host "========================================"
    Write-Host ""
    Get-Content $markdownOutput | Write-Host
}

Write-Host ""
Write-Host "========================================"
Write-Host "✓ Overmind Analysis Complete"
Write-Host "========================================"
Write-Host ""
Write-Host "Results saved to: $OutputDir"
if ($changeUrl) {
    Write-Host "View interactive visualization: $changeUrl" -ForegroundColor Cyan
}
Write-Host ""

# Upload results as artifacts if in Buildkite
if (Get-Command "buildkite-agent" -ErrorAction SilentlyContinue) {
    Write-Host "--- 📤 Uploading results to Buildkite"
    buildkite-agent artifact upload "$OutputDir/*"
    
    # Add annotation with results summary
    if (Test-Path $markdownOutput) {
        $annotation = @"
## 🔍 Overmind Blast Radius Analysis - $Environment

$changeUrl

$(Get-Content $markdownOutput -Raw)

[View full interactive analysis]($changeUrl)
"@
        $annotation | buildkite-agent annotate --style info --context "overmind-$Environment"
    }
}

# Exit with appropriate code based on risks
if (Test-Path $jsonOutput) {
    try {
        $analysis = Get-Content $jsonOutput | ConvertFrom-Json
        $riskCount = ($analysis.properties.risks | Measure-Object).Count
        $highRisks = ($analysis.properties.risks | Where-Object { $_.severity -eq "high" } | Measure-Object).Count
        
        if ($highRisks -gt 0) {
            Write-Host "⚠ WARNING: $highRisks high-severity risks detected!" -ForegroundColor Red
            Write-Host "Review the analysis before proceeding with deployment." -ForegroundColor Yellow
            # Don't fail the build, just warn
            exit 0
        }
        elseif ($riskCount -gt 0) {
            Write-Host "⚠ Note: $riskCount risk(s) identified - review recommended" -ForegroundColor Yellow
            exit 0
        }
        else {
            Write-Host "✓ No risks identified" -ForegroundColor Green
            exit 0
        }
    }
    catch {
        Write-Host "⚠ Could not evaluate risks" -ForegroundColor Yellow
        exit 0
    }
}

exit 0
