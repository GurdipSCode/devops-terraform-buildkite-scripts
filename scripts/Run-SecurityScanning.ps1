# scripts/Check-TerraformFormatting.ps1
<#
.SYNOPSIS
    Validates Terraform code formatting and structure

.DESCRIPTION
    Checks Terraform files for proper formatting, trailing whitespace,
    and required file structure.
#>

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Terraform Formatting & Structure Validation"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""

$hasErrors = $false

# Check OpenTofu formatting
Write-Host "--- Checking OpenTofu formatting"
tofu fmt -check -recursive

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Code is not formatted correctly"
    Write-Host ""
    Write-Host "To fix formatting issues, run:"
    Write-Host "  tofu fmt -recursive"
    Write-Host ""
    $hasErrors = $true
} else {
    Write-Host "✅ Code formatting is correct"
}

Write-Host ""

# Check for trailing whitespace
Write-Host "--- Checking for trailing whitespace"
$files = Get-ChildItem -Recurse -Filter "*.tf" | Where-Object { 
    (Get-Content $_.FullName -Raw) -match '\s+$' 
}

if ($files) {
    Write-Host "❌ Trailing whitespace found in:"
    $files | ForEach-Object { Write-Host "  - $($_.FullName)" }
    Write-Host ""
    Write-Host "To fix: Remove trailing whitespace from the files above"
    $hasErrors = $true
} else {
    Write-Host "✅ No trailing whitespace found"
}

Write-Host ""

# Validate required files exist
Write-Host "--- Validating required files"
$requiredFiles = @("main.tf", "variables.tf", "outputs.tf", "versions.tf")
$missing = @()

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $missing += $file
    }
}

if ($missing.Count -gt 0) {
    Write-Host "❌ Required files missing:"
    $missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    $hasErrors = $true
} else {
    Write-Host "✅ All required files present"
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════"

if ($hasErrors) {
    Write-Host "❌ Formatting validation failed"
    Write-Host "═══════════════════════════════════════════════════════════════"
    exit 1
} else {
    Write-Host "✅ All formatting checks passed"
    Write-Host "═══════════════════════════════════════════════════════════════"
    exit 0
}
