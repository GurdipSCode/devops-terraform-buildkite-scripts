<#
.SYNOPSIS
    Runs PSScriptAnalyzer on all PowerShell scripts in the repository.
.DESCRIPTION
    Lints PowerShell scripts using PSScriptAnalyzer with project settings.
    Returns exit code 1 if errors found, 0 otherwise.
.PARAMETER Path
    Path to scan. Defaults to current directory.
.PARAMETER SettingsPath
    Path to PSScriptAnalyzer settings file. Defaults to PSScriptAnalyzerSettings.psd1.
.PARAMETER FailOnWarning
    Fail the build on warnings, not just errors.
.EXAMPLE
    .\Invoke-PSScriptAnalyzer.ps1
.EXAMPLE
    .\Invoke-PSScriptAnalyzer.ps1 -Path .\scripts -FailOnWarning
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = ".",

    [Parameter()]
    [string]$SettingsPath = "PSScriptAnalyzerSettings.psd1",

    [Parameter()]
    [switch]$FailOnWarning
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Install PSScriptAnalyzer if needed
# ============================================================================
Write-Host "Checking PSScriptAnalyzer..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "Installing PSScriptAnalyzer..." -ForegroundColor Yellow
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck
}

Import-Module PSScriptAnalyzer -Force

# ============================================================================
# Find scripts to analyze
# ============================================================================
Write-Host "Scanning for PowerShell scripts in: $Path" -ForegroundColor Cyan

$scripts = Get-ChildItem -Path $Path -Include "*.ps1", "*.psm1", "*.psd1" -Recurse -File |
    Where-Object { $_.FullName -notmatch "\\\.git\\" }

if ($scripts.Count -eq 0) {
    Write-Host "No PowerShell scripts found" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($scripts.Count) script(s) to analyze" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Run analysis
# ============================================================================
$analyzerParams = @{
    Path        = $Path
    Recurse     = $true
    ReportSummary = $true
}

if (Test-Path $SettingsPath) {
    Write-Host "Using settings file: $SettingsPath" -ForegroundColor Cyan
    $analyzerParams.Settings = $SettingsPath
} else {
    Write-Host "Settings file not found, using defaults" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Gray

$results = Invoke-ScriptAnalyzer @analyzerParams

# ============================================================================
# Process results
# ============================================================================
$errors = $results | Where-Object { $_.Severity -eq 'Error' }
$warnings = $results | Where-Object { $_.Severity -eq 'Warning' }
$information = $results | Where-Object { $_.Severity -eq 'Information' }

Write-Host ""
Write-Host "================================================" -ForegroundColor Gray
Write-Host "Analysis Complete" -ForegroundColor Cyan
Write-Host ""

# Display summary
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Errors:      $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Warnings:    $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Information: $($information.Count)" -ForegroundColor Gray
Write-Host ""

# Display issues by file
if ($results.Count -gt 0) {
    $groupedResults = $results | Group-Object -Property ScriptPath

    foreach ($group in $groupedResults) {
        $relativePath = $group.Name -replace [regex]::Escape((Get-Location).Path + "\"), ""
        Write-Host "📄 $relativePath" -ForegroundColor White

        foreach ($issue in $group.Group) {
            $icon = switch ($issue.Severity) {
                'Error'       { "❌" }
                'Warning'     { "⚠️" }
                'Information' { "ℹ️" }
            }
            $color = switch ($issue.Severity) {
                'Error'       { 'Red' }
                'Warning'     { 'Yellow' }
                'Information' { 'Gray' }
            }

            Write-Host "  $icon Line $($issue.Line): $($issue.Message)" -ForegroundColor $color
            Write-Host "     Rule: $($issue.RuleName)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

# ============================================================================
# Determine exit code
# ============================================================================
$exitCode = 0

if ($errors.Count -gt 0) {
    Write-Host "❌ BUILD FAILED: $($errors.Count) error(s) found" -ForegroundColor Red
    $exitCode = 1
} elseif ($FailOnWarning -and $warnings.Count -gt 0) {
    Write-Host "❌ BUILD FAILED: $($warnings.Count) warning(s) found (FailOnWarning enabled)" -ForegroundColor Red
    $exitCode = 1
} else {
    Write-Host "✅ All checks passed" -ForegroundColor Green
}

exit $exitCode
