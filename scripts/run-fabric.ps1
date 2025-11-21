#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Uses Fabric CLI to summarize Terraform changes
.DESCRIPTION
    Runs Fabric CLI to create AI-powered summaries of Terraform plans
.PARAMETER PlanFile
    Path to the Terraform plan file
.PARAMETER Environment
    Environment name for context
.PARAMETER Pattern
    Fabric pattern to use (default: summarize)
.EXAMPLE
    .\run-fabric-summary.ps1 -PlanFile "tfplan-dev.txt" -Environment "dev"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PlanFile,
    
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    
    [string]$Pattern = "summarize"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "🤖 Generating AI Summary with Fabric"
Write-Host "========================================"
Write-Host "Environment: $Environment"
Write-Host "Plan File: $PlanFile"
Write-Host "Pattern: $Pattern"
Write-Host ""

# Check if Fabric is installed
if (-not (Get-Command "fabric" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Error: Fabric CLI not found" -ForegroundColor Red
    Write-Host "Install it with: go install github.com/danielmiessler/fabric@latest" -ForegroundColor Yellow
    exit 1
}

# Check if plan file exists
if (-not (Test-Path $PlanFile)) {
    Write-Host "❌ Error: Plan file not found: $PlanFile" -ForegroundColor Red
    exit 1
}

# Run Fabric to summarize the plan
Write-Host "--- 🧠 Analyzing Terraform plan with AI"
try {
    $summary = Get-Content $PlanFile | fabric --pattern $Pattern
    
    Write-Host ""
    Write-Host "========================================"
    Write-Host "📝 AI Summary for $Environment"
    Write-Host "========================================"
    Write-Host ""
    Write-Host $summary
    Write-Host ""
    
    # Save summary to file
    $summaryFile = "fabric-summary-$Environment.md"
    @"
# Terraform Plan Summary - $Environment
**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Environment**: $Environment
**Pattern**: $Pattern

## AI Analysis

$summary

## Original Plan
See artifact: $PlanFile
"@ | Out-File -FilePath $summaryFile -Encoding UTF8
    
    Write-Host "✓ Summary saved to $summaryFile" -ForegroundColor Green
    
    # Upload as artifact if in Buildkite
    if (Get-Command "buildkite-agent" -ErrorAction SilentlyContinue) {
        buildkite-agent artifact upload $summaryFile
        Write-Host "✓ Summary uploaded to Buildkite artifacts" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠ Warning: Failed to generate Fabric summary: $_" -ForegroundColor Yellow
    Write-Host "Continuing without AI summary..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================"
Write-Host "✓ Fabric Analysis Complete"
Write-Host "========================================"
