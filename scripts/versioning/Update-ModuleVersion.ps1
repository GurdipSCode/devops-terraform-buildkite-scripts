#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates the Terraform module version and generates changelog.

.DESCRIPTION
    This script:
    - Reads the next version from next-version.txt
    - Updates version.tf with the new version
    - Generates CHANGELOG.md using git-cliff
    - Prepares files for commit

.PARAMETER Version
    The version to set (default: read from next-version.txt)

.PARAMETER ChangelogConfig
    Path to git-cliff configuration (default: cliff.toml)

.EXAMPLE
    .\Update-ModuleVersion.ps1
    # Uses version from next-version.txt

.EXAMPLE
    .\Update-ModuleVersion.ps1 -Version "1.2.3"
    # Uses explicit version
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,

    [Parameter()]
    [string]$ChangelogConfig = "cliff.toml",

    [Parameter()]
    [string]$VersionFile = "version.tf"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Update-VersionFile {
    param(
        [string]$FilePath,
        [string]$NewVersion
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Info "Creating new version.tf file..."
        $content = @"
# Module Version
# This file is automatically updated by CI/CD pipeline
# Do not manually edit this file

variable "module_version" {
  description = "The version of this Terraform module"
  type        = string
  default     = "$NewVersion"
}

output "module_version" {
  description = "The version of this Terraform module"
  value       = var.module_version
}
"@
        Set-Content -Path $FilePath -Value $content -NoNewline
        return
    }
    
    $content = Get-Content -Path $FilePath -Raw
    
    if ($content -match 'default\s*=\s*"([^"]+)"') {
        $oldVersion = $matches[1]
        Write-Info "Current version: $oldVersion"
        $content = $content -replace 'default\s*=\s*"[^"]+"', "default     = `"$NewVersion`""
        Set-Content -Path $FilePath -Value $content -NoNewline
        Write-Success "Updated version.tf: $oldVersion → $NewVersion"
    } else {
        throw "Could not find version string in $FilePath"
    }
}

function New-Changelog {
    param(
        [string]$Version,
        [string]$ConfigPath
    )
    
    if (-not (Test-CommandExists "git-cliff")) {
        throw "git-cliff is not installed. Install it from: https://github.com/orhun/git-cliff"
    }
    
    Write-Info "Generating changelog with git-cliff..."
    
    $args = @("--tag", "v$Version")
    
    if (Test-Path $ConfigPath) {
        $args += "--config", $ConfigPath
    }
    
    $args += "--output", "CHANGELOG.md"
    
    & git-cliff @args
    
    if ($LASTEXITCODE -ne 0) {
        throw "git-cliff failed with exit code $LASTEXITCODE"
    }
    
    Write-Success "Generated CHANGELOG.md"
}

function Update-ReadmeVersion {
    param([string]$NewVersion)
    
    if (-not (Test-Path "README.md")) {
        Write-Info "No README.md found, skipping version update"
        return
    }
    
    $content = Get-Content -Path "README.md" -Raw
    $updated = $false
    
    if ($content -match '(?m)^##\s+Version\s*$.*?-\s+Current:\s+`v?([^`]+)`') {
        $content = $content -replace '(##\s+Version\s*$.*?-\s+Current:\s+`)v?[^`]+(`)','$1'+"$NewVersion"+'$2'
        $updated = $true
    }
    
    if ($content -match 'source\s*=\s*"[^"]+\?ref=v?([^"]+)"') {
        $content = $content -replace '(\?ref=)v?[^"]+', '$1v' + $NewVersion
        $updated = $true
    }
    
    if ($updated) {
        Set-Content -Path "README.md" -Value $content -NoNewline
        Write-Success "Updated version references in README.md"
    }
}

#endregion

#region Main Logic

try {
    Write-Info "Starting module version update..."
    
    if (-not $Version) {
        if (Test-Path "next-version.txt") {
            $Version = Get-Content "next-version.txt" -Raw
            $Version = $Version.Trim()
            Write-Info "Read version from next-version.txt: $Version"
        } else {
            throw "No version specified and next-version.txt not found"
        }
    }
    
    if ($Version -notmatch '^\d+\.\d+\.\d+') {
        throw "Invalid version format: $Version (expected semver like 1.2.3)"
    }
    
    Write-Host ""
    Write-Host "📦 Updating Module to Version: $Version" -ForegroundColor Magenta
    Write-Host ""
    
    Update-VersionFile -FilePath $VersionFile -NewVersion $Version
    
    New-Changelog -Version $Version -ConfigPath $ChangelogConfig
    
    Update-ReadmeVersion -NewVersion $Version
    
    $changedFiles = @()
    if (Test-Path $VersionFile) { $changedFiles += $VersionFile }
    if (Test-Path "CHANGELOG.md") { $changedFiles += "CHANGELOG.md" }
    if (Test-Path "README.md") {
        $status = git status --porcelain README.md 2>$null
        if ($status) { $changedFiles += "README.md" }
    }
    
    Write-Host ""
    Write-Success "Module version update complete!"
    Write-Host ""
    Write-Host "📝 Changed Files:" -ForegroundColor Yellow
    foreach ($file in $changedFiles) {
        Write-Host "  - $file" -ForegroundColor White
    }
    
    Set-Content -Path "changed-files.txt" -Value ($changedFiles -join "`n") -NoNewline
    
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "  1. Review the changes" -ForegroundColor White
    Write-Host "  2. Run Publish-GitChanges.ps1 to commit and tag" -ForegroundColor White
    
} catch {
    Write-Error "Failed to update module version: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

#endregion
