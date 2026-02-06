#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Calculate next semantic version using git-cliff for PR and main builds.

.DESCRIPTION
    This script determines the next version based on conventional commits:
    - For main branch: Creates stable releases (e.g., 1.2.3)
    - For PR builds: Creates prerelease versions (e.g., 1.2.3-pr.123.1)
    
    Version bump rules (based on conventional commits):
    - feat!: or BREAKING CHANGE → Major (1.0.0 → 2.0.0)
    - feat: → Minor (1.0.0 → 1.1.0)
    - fix:, chore:, docs:, etc. → Patch (1.0.0 → 1.0.1)

.PARAMETER Branch
    The branch name (default: auto-detected from git or BUILDKITE_BRANCH)

.PARAMETER PullRequestNumber
    The PR number (default: auto-detected from BUILDKITE_PULL_REQUEST)

.EXAMPLE
    .\Get-NextVersion.ps1
    # Auto-detects branch and calculates version

.EXAMPLE
    .\Get-NextVersion.ps1 -Branch "feature/new-feature" -PullRequestNumber 123
    # Outputs: 1.2.3-pr.123.1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Branch = $env:BUILDKITE_BRANCH,

    [Parameter()]
    [string]$PullRequestNumber = $env:BUILDKITE_PULL_REQUEST
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

function Get-LatestTag {
    $tags = git tag --sort=-v:refname --merged HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tags) {
        return $null
    }
    
    foreach ($tag in $tags) {
        if ($tag -match '^v?\d+\.\d+\.\d+$') {
            return $tag
        }
    }
    
    return $null
}

function Get-CommitsSinceTag {
    param([string]$Tag)
    
    if ($Tag) {
        $range = "$Tag..HEAD"
    } else {
        $range = "HEAD"
    }
    
    $commits = git log $range --pretty=format:"%s" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }
    
    return $commits -split "`n" | Where-Object { $_ }
}

function Get-VersionBumpType {
    param([string[]]$Commits)
    
    $hasMajor = $false
    $hasMinor = $false
    $hasPatch = $false
    
    foreach ($commit in $Commits) {
        if ($commit -match '^[a-z]+(\([^)]+\))?!:' -or $commit -match 'BREAKING[- ]CHANGE:') {
            $hasMajor = $true
            break
        }
        
        if ($commit -match '^feat(\([^)]+\))?:') {
            $hasMinor = $true
        }
        
        if ($commit -match '^(fix|perf|refactor|style|test|build|ci|chore|docs)(\([^)]+\))?:') {
            $hasPatch = $true
        }
    }
    
    if ($hasMajor) { return "major" }
    if ($hasMinor) { return "minor" }
    if ($hasPatch) { return "patch" }
    
    return "patch"
}

function Get-NextSemanticVersion {
    param(
        [string]$CurrentVersion,
        [string]$BumpType
    )
    
    if ($CurrentVersion -match '^v?(\d+)\.(\d+)\.(\d+)') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        
        switch ($BumpType) {
            "major" {
                $major++
                $minor = 0
                $patch = 0
            }
            "minor" {
                $minor++
                $patch = 0
            }
            "patch" {
                $patch++
            }
        }
        
        return "$major.$minor.$patch"
    }
    
    return "0.1.0"
}

function Get-PrereleaseCount {
    param(
        [string]$BaseVersion,
        [string]$PrNumber
    )
    
    $pattern = "^v?$([regex]::Escape($BaseVersion))-pr\.$PrNumber\.(\d+)$"
    $tags = git tag -l 2>$null | Where-Object { $_ -match $pattern }
    
    if (-not $tags) {
        return 1
    }
    
    $counts = $tags | ForEach-Object {
        if ($_ -match $pattern) {
            [int]$matches[1]
        }
    }
    
    return ($counts | Measure-Object -Maximum).Maximum + 1
}

#endregion

#region Main Logic

try {
    Write-Info "Starting version calculation..."
    
    if (-not (Test-CommandExists "git")) {
        throw "git is not installed or not in PATH"
    }
    
    if (-not $Branch) {
        $Branch = git rev-parse --abbrev-ref HEAD
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to detect current branch"
        }
    }
    
    Write-Info "Branch: $Branch"
    if ($PullRequestNumber -and $PullRequestNumber -ne "false") {
        Write-Info "Pull Request: #$PullRequestNumber"
    }
    
    $latestTag = Get-LatestTag
    if ($latestTag) {
        Write-Info "Latest tag: $latestTag"
        $currentVersion = $latestTag -replace '^v', ''
    } else {
        Write-Info "No previous tags found, starting from 0.0.0"
        $currentVersion = "0.0.0"
    }
    
    $commits = Get-CommitsSinceTag -Tag $latestTag
    if ($commits.Count -eq 0) {
        Write-Info "No new commits since last tag"
        Write-Output $currentVersion
        Set-Content -Path "next-version.txt" -Value $currentVersion -NoNewline
        Set-Content -Path "version-type.txt" -Value "none" -NoNewline
        Write-Success "Version: $currentVersion (no changes)"
        exit 0
    }
    
    Write-Info "Analyzing $($commits.Count) commit(s)..."
    $bumpType = Get-VersionBumpType -Commits $commits
    Write-Info "Version bump type: $bumpType"
    
    $nextVersion = Get-NextSemanticVersion -CurrentVersion $currentVersion -BumpType $bumpType
    
    $isPullRequest = $PullRequestNumber -and $PullRequestNumber -ne "false"
    $isMainBranch = $Branch -match '^(main|master)$'
    
    if ($isPullRequest) {
        $prereleaseCount = Get-PrereleaseCount -BaseVersion $nextVersion -PrNumber $PullRequestNumber
        $finalVersion = "$nextVersion-pr.$PullRequestNumber.$prereleaseCount"
        $versionType = "prerelease"
        Write-Info "Creating prerelease version for PR #$PullRequestNumber"
    } elseif ($isMainBranch) {
        $finalVersion = $nextVersion
        $versionType = "release"
        Write-Info "Creating stable release version"
    } else {
        $branchName = $Branch -replace '[^a-zA-Z0-9]', '-'
        $shortSha = git rev-parse --short HEAD
        $finalVersion = "$nextVersion-$branchName.$shortSha"
        $versionType = "prerelease"
        Write-Info "Creating branch prerelease version"
    }
    
    Write-Output $finalVersion
    Set-Content -Path "next-version.txt" -Value $finalVersion -NoNewline
    Set-Content -Path "version-type.txt" -Value $versionType -NoNewline
    Set-Content -Path "version-bump-type.txt" -Value $bumpType -NoNewline
    
    Write-Success "Next version: $finalVersion"
    Write-Success "Version type: $versionType"
    Write-Success "Bump type: $bumpType"
    
    Write-Host ""
    Write-Host "📦 Version Details:" -ForegroundColor Magenta
    Write-Host "  Current: $currentVersion" -ForegroundColor White
    Write-Host "  Next:    $finalVersion" -ForegroundColor Yellow
    Write-Host "  Type:    $versionType" -ForegroundColor White
    Write-Host "  Bump:    $bumpType" -ForegroundColor White
    
} catch {
    Write-Error "Failed to calculate version: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

#endregion
