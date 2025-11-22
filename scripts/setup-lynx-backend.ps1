#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures Terraform HTTP backend for Lynx
.DESCRIPTION
    Sets up environment variables for Terraform to use Lynx backend
    Expects LYNX_USERNAME and LYNX_PASSWORD to be already loaded from Vault
.PARAMETER Environment
    The environment (dev, tst, prd, etc.)
.EXAMPLE
    .\configure-lynx-backend.ps1 -Environment dev
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

Write-Host "--- 🔧 Configuring Lynx Backend for $Environment"

# Check required environment variables
# LYNX_USERNAME and LYNX_PASSWORD should come from fetch-vault-secrets.ps1
$requiredVars = @('LYNX_SERVER_URL', 'LYNX_USERNAME', 'LYNX_PASSWORD', 'LYNX_TEAM', 'LYNX_PROJECT')
$missing = @()

foreach ($var in $requiredVars) {
    if (-not (Get-Item -Path "env:$var" -ErrorAction SilentlyContinue)) {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host "❌ Error: Missing required environment variables:" -ForegroundColor Red
    foreach ($var in $missing) {
        Write-Host "  - $var" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Note: LYNX_USERNAME and LYNX_PASSWORD should be loaded from Vault via fetch-vault-secrets.ps1" -ForegroundColor Yellow
    Write-Host "LYNX_SERVER_URL, LYNX_TEAM, and LYNX_PROJECT should be set in Buildkite" -ForegroundColor Yellow
    exit 1
}

# Set Terraform HTTP backend credentials
$env:TF_HTTP_USERNAME = $env:LYNX_USERNAME
$env:TF_HTTP_PASSWORD = $env:LYNX_PASSWORD

# Construct Lynx endpoint URLs
$lynxBase = "$env:LYNX_SERVER_URL/client/$env:LYNX_TEAM/$env:LYNX_PROJECT/$Environment"
$env:TF_HTTP_ADDRESS = "$lynxBase/state"
$env:TF_HTTP_LOCK_ADDRESS = "$lynxBase/lock"
$env:TF_HTTP_UNLOCK_ADDRESS = "$lynxBase/unlock"
$env:TF_HTTP_LOCK_METHOD = "POST"
$env:TF_HTTP_UNLOCK_METHOD = "POST"

Write-Host "✓ Backend configured successfully" -ForegroundColor Green
Write-Host "  Team: $env:LYNX_TEAM"
Write-Host "  Project: $env:LYNX_PROJECT"
Write-Host "  Environment: $Environment"
Write-Host "  Server: $env:LYNX_SERVER_URL"
Write-Host "  Username: $env:LYNX_USERNAME"
Write-Host "  State URL: $env:TF_HTTP_ADDRESS"
