#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates Terraform configuration
.DESCRIPTION
    Runs terraform fmt check and terraform validate
#>

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "✅ Terraform Validation"
Write-Host "========================================"

$exitCode = 0

# Terraform Format Check
Write-Host ""
Write-Host "--- 📝 Checking Terraform formatting"
try {
    terraform fmt -check -recursive -diff
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ All files are properly formatted" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Some files need formatting" -ForegroundColor Red
        Write-Host "Run 'terraform fmt -recursive' to fix" -ForegroundColor Yellow
        $exitCode = 1
    }
}
catch {
    Write-Host "❌ Error checking format: $_" -ForegroundColor Red
    $exitCode = 1
}

# Terraform Init (without backend)
Write-Host ""
Write-Host "--- 🔧 Initializing Terraform (validation mode)"
try {
    terraform init -backend=false -input=false
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Terraform initialized" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Terraform init failed" -ForegroundColor Red
        $exitCode = 1
    }
}
catch {
    Write-Host "❌ Error during init: $_" -ForegroundColor Red
    $exitCode = 1
}

# Terraform Validate
Write-Host ""
Write-Host "--- ✅ Validating Terraform configuration"
try {
    terraform validate
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Configuration is valid" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Configuration validation failed" -ForegroundColor Red
        $exitCode = 1
    }
}
catch {
    Write-Host "❌ Error during validation: $_" -ForegroundColor Red
    $exitCode = 1
}

# Summary
Write-Host ""
Write-Host "========================================"
if ($exitCode -eq 0) {
    Write-Host "✓ Validation Complete - All Checks Passed" -ForegroundColor Green
}
else {
    Write-Host "❌ Validation Failed" -ForegroundColor Red
}
Write-Host "========================================"

exit $exitCode
