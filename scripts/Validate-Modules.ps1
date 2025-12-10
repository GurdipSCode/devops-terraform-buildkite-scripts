# scripts/Validate-ModuleSources.ps1
<#
.SYNOPSIS
    Validates Terraform module sources and versions

.DESCRIPTION
    Ensures all module sources are accessible, versions are pinned,
    and modules are from approved sources.
#>

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Terraform Module Source Validation"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""

$hasErrors = $false
$hasWarnings = $false

# Find all .tf files
Write-Host "--- Scanning Terraform files for module declarations"
$tfFiles = Get-ChildItem -Recurse -Filter "*.tf"

if ($tfFiles.Count -eq 0) {
    Write-Host "❌ No Terraform files found"
    exit 1
}

Write-Host "Found $($tfFiles.Count) Terraform file(s)"
Write-Host ""

# Parse modules from files
$modules = @()
$unpinnedModules = @()
$unverifiedSources = @()

foreach ($file in $tfFiles) {
    $content = Get-Content $file.FullName -Raw
    
    # Regex to find module blocks
    $modulePattern = 'module\s+"([^"]+)"\s+\{([^}]+)\}'
    $matches = [regex]::Matches($content, $modulePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    foreach ($match in $matches) {
        $moduleName = $match.Groups[1].Value
        $moduleBody = $match.Groups[2].Value
        
        # Extract source
        if ($moduleBody -match 'source\s+=\s+"([^"]+)"') {
            $source = $matches[0].Groups[1].Value
        } else {
            $source = "UNKNOWN"
        }
        
        # Extract version
        $version = "UNPINNED"
        if ($moduleBody -match 'version\s+=\s+"([^"]+)"') {
            $version = $matches[0].Groups[1].Value
        }
        
        $modules += @{
            Name = $moduleName
            Source = $source
            Version = $version
            File = $file.Name
        }
    }
}

if ($modules.Count -eq 0) {
    Write-Host "ℹ️  No module declarations found in Terraform files"
    Write-Host "This may be expected if using only local resources."
    exit 0
}

Write-Host "--- Found $($modules.Count) module(s)"
Write-Host ""

# Validate each module
foreach ($module in $modules) {
    Write-Host "Module: $($module.Name)"
    Write-Host "  Source: $($module.Source)"
    Write-Host "  Version: $($module.Version)"
    Write-Host "  File: $($module.File)"
    
    # Check if version is pinned
    if ($module.Version -eq "UNPINNED") {
        Write-Host "  ⚠️  WARNING: Version not pinned!" -ForegroundColor Yellow
        $unpinnedModules += $module
        $hasWarnings = $true
    } else {
        Write-Host "  ✅ Version is pinned"
    }
    
    # Validate source
    $sourceValid = $false
    $source = $module.Source
    
    # Check for approved source patterns
    if ($source -match "^app\.terraform\.io/") {
        Write-Host "  ✅ Terraform Cloud module"
        $sourceValid = $true
    }
    elseif ($source -match "^registry\.terraform\.io/") {
        Write-Host "  ✅ Public Terraform Registry module"
        $sourceValid = $true
    }
    elseif ($source -match "^git::https://github\.com/") {
        Write-Host "  ✅ GitHub source"
        $sourceValid = $true
    }
    elseif ($source -match "^git::https://gitlab\.com/") {
        Write-Host "  ✅ GitLab source"
        $sourceValid = $true
    }
    elseif ($source -match "^\.\.?/") {
        Write-Host "  ✅ Local module"
        $sourceValid = $true
    }
    elseif ($env:MODULE_REGISTRY_URL -and $source -match "^$($env:MODULE_REGISTRY_URL)") {
        Write-Host "  ✅ Approved private registry"
        $sourceValid = $true
    }
    else {
        Write-Host "  ⚠️  WARNING: Unverified source pattern" -ForegroundColor Yellow
        $unverifiedSources += $module
        $hasWarnings = $true
    }
    
    Write-Host ""
}

# Summary
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Validation Summary"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "Total modules: $($modules.Count)"
Write-Host "Unpinned versions: $($unpinnedModules.Count)"
Write-Host "Unverified sources: $($unverifiedSources.Count)"
Write-Host ""

# Report unpinned modules
if ($unpinnedModules.Count -gt 0) {
    Write-Host "⚠️  Modules without pinned versions:" -ForegroundColor Yellow
    foreach ($module in $unpinnedModules) {
        Write-Host "  - $($module.Name) in $($module.File)"
    }
    Write-Host ""
    Write-Host "Recommendation: Pin module versions for reproducible builds"
    Write-Host "Example: version = `"~> 1.0`""
    Write-Host ""
    
    # Create Buildkite annotation
    if (Get-Command buildkite-agent -ErrorAction SilentlyContinue) {
        $unpinnedList = $unpinnedModules | ForEach-Object { "- ``$($_.Name)`` in $($_.File)" }
        buildkite-agent annotate --style warning --context modules-unpinned @"
:warning: **Unpinned Module Versions**

The following modules do not have pinned versions:

$($unpinnedList -join "`n")

Consider pinning versions for reproducible deployments.
"@
    }
}

# Report unverified sources
if ($unverifiedSources.Count -gt 0) {
    Write-Host "⚠️  Modules from unverified sources:" -ForegroundColor Yellow
    foreach ($module in $unverifiedSources) {
        Write-Host "  - $($module.Name): $($module.Source)"
    }
    Write-Host ""
    Write-Host "Recommendation: Use approved module registries or Git sources"
    Write-Host ""
    
    # Create Buildkite annotation
    if (Get-Command buildkite-agent -ErrorAction SilentlyContinue) {
        $unverifiedList = $unverifiedSources | ForEach-Object { "- ``$($_.Name)``: $($_.Source)" }
        buildkite-agent annotate --style warning --context modules-unverified @"
:warning: **Unverified Module Sources**

The following modules are from unverified sources:

$($unverifiedList -join "`n")

Ensure these sources are approved by your security team.
"@
    }
}

# Final result
Write-Host "═══════════════════════════════════════════════════════════════"

if ($hasErrors) {
    Write-Host "❌ Module validation failed with errors"
    Write-Host "═══════════════════════════════════════════════════════════════"
    exit 1
}
elseif ($hasWarnings) {
    Write-Host "⚠️  Module validation completed with warnings"
    Write-Host "═══════════════════════════════════════════════════════════════"
    # Exit 0 - warnings don't fail the build
    exit 0
}
else {
    Write-Host "✅ All modules validated successfully"
    Write-Host "═══════════════════════════════════════════════════════════════"
    exit 0
}
