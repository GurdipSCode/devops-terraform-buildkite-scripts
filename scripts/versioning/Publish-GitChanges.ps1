#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Commits changes, creates git tags, and pushes to GitHub with GPG signing.

.DESCRIPTION
    This script:
    - Configures git with SSH key for authentication
    - Imports GPG key for commit signing
    - Commits version changes with GPG signature
    - Creates annotated git tag
    - Pushes commits and tags to GitHub

.PARAMETER Version
    The version to tag (default: read from next-version.txt)

.PARAMETER SshKeyPath
    Path to SSH private key file (default: $env:SSH_KEY_PATH or ~/.ssh/id_ed25519)

.PARAMETER GpgKey
    GPG private key (ASCII armored) or path to key file (default: $env:GPG_PRIVATE_KEY)

.PARAMETER GpgPassphrase
    GPG key passphrase (default: $env:GPG_PASSPHRASE)

.PARAMETER GitUserName
    Git user name for commits (default: $env:GIT_USER_NAME or "CI/CD Bot")

.PARAMETER GitUserEmail
    Git user email for commits (default: $env:GIT_USER_EMAIL or "cicd@example.com")

.PARAMETER RemoteName
    Git remote name (default: origin)

.PARAMETER Branch
    Branch to push to (default: current branch or main)

.PARAMETER DryRun
    If set, shows what would be done without making changes

.EXAMPLE
    .\Publish-GitChanges.ps1
    # Uses environment variables for credentials

.EXAMPLE
    .\Publish-GitChanges.ps1 -Version "1.2.3" -DryRun
    # Dry run for version 1.2.3
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,

    [Parameter()]
    [string]$SecretsDir = ".secrets",

    [Parameter()]
    [string]$SshKeyPath,

    [Parameter()]
    [string]$GpgKey,

    [Parameter()]
    [string]$GpgPassphrase,

    [Parameter()]
    [string]$GitUserName,

    [Parameter()]
    [string]$GitUserEmail,

    [Parameter()]
    [string]$RemoteName = "origin",

    [Parameter()]
    [string]$Branch,

    [Parameter()]
    [switch]$DryRun
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

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-VaultSecret {
    param(
        [string]$SecretsDir,
        [string]$SecretName
    )
    
    $secretPath = Join-Path $SecretsDir "$SecretName.txt"
    
    if (Test-Path $secretPath) {
        Write-Info "Loading $SecretName from Vault secrets..."
        return Get-Content -Path $secretPath -Raw
    }
    
    if ($env:$SecretName) {
        Write-Info "Loading $SecretName from environment variable..."
        return $env:$SecretName
    }
    
    return $null
}

function Initialize-SshAgent {
    param([string]$KeyPath)
    
    Write-Info "Configuring SSH authentication..."
    
    if (-not $KeyPath) {
        $KeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
        if ($IsLinux -or $IsMacOS) {
            $KeyPath = "$env:HOME/.ssh/id_ed25519"
        }
    }
    
    if (Test-Path $KeyPath) {
        Write-Info "Using SSH key from file: $KeyPath"
    } else {
        if ($env:SSH_PRIVATE_KEY) {
            Write-Info "Using SSH key from environment variable"
            $tempKeyPath = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tempKeyPath -Value $env:SSH_PRIVATE_KEY -NoNewline
            if ($IsLinux -or $IsMacOS) {
                chmod 600 $tempKeyPath
            }
            $KeyPath = $tempKeyPath
        } else {
            throw "No SSH key found. Set SSH_KEY_PATH or SSH_PRIVATE_KEY environment variable"
        }
    }
    
    if ($IsWindows) {
        $env:GIT_SSH_COMMAND = "ssh -i `"$KeyPath`" -o StrictHostKeyChecking=no"
    } else {
        & eval `ssh-agent -s` 2>&1 | Out-Null
        & ssh-add $KeyPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add SSH key to agent"
        }
    }
    
    Write-Success "SSH authentication configured"
}

function Initialize-GpgKey {
    param(
        [string]$Key,
        [string]$Passphrase
    )
    
    Write-Info "Configuring GPG signing..."
    
    if (-not (Test-CommandExists "gpg")) {
        throw "GPG is not installed. Install GnuPG from: https://gnupg.org/download/"
    }
    
    if (-not $Key) {
        throw "No GPG key provided. Set GPG_PRIVATE_KEY environment variable"
    }
    
    $keyContent = $Key
    if (Test-Path $Key) {
        Write-Info "Reading GPG key from file: $Key"
        $keyContent = Get-Content -Path $Key -Raw
    }
    
    $tempKeyFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempKeyFile -Value $keyContent -NoNewline
    
    try {
        Write-Info "Importing GPG key..."
        $importOutput = & gpg --batch --import $tempKeyFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to import GPG key: $importOutput"
        }
        
        $keyId = & gpg --list-secret-keys --keyid-format LONG 2>&1 | Select-String -Pattern "sec\s+\w+/([A-F0-9]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        
        if (-not $keyId) {
            throw "Could not extract GPG key ID"
        }
        
        Write-Info "GPG Key ID: $keyId"
        
        & git config --global user.signingkey $keyId
        & git config --global commit.gpgsign true
        & git config --global tag.gpgsign true
        
        if ($Passphrase) {
            $env:GPG_TTY = $(tty)
            if ($IsWindows) {
                $gpgConfDir = "$env:APPDATA\gnupg"
            } else {
                $gpgConfDir = "$env:HOME/.gnupg"
            }
            
            if (-not (Test-Path $gpgConfDir)) {
                New-Item -ItemType Directory -Path $gpgConfDir -Force | Out-Null
            }
            
            $gpgAgentConf = Join-Path $gpgConfDir "gpg-agent.conf"
            @"
allow-preset-passphrase
max-cache-ttl 3600
default-cache-ttl 3600
"@ | Set-Content -Path $gpgAgentConf
            
            & gpg-connect-agent reloadagent /bye 2>&1 | Out-Null
        }
        
        Write-Success "GPG signing configured (Key ID: $keyId)"
        return $keyId
        
    } finally {
        Remove-Item -Path $tempKeyFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-GitConfig {
    param(
        [string]$UserName,
        [string]$UserEmail
    )
    
    if (-not $UserName) {
        $UserName = "Buildkite CI"
    }
    
    if (-not $UserEmail) {
        $UserEmail = "ci@buildkite.local"
    }
    
    Write-Info "Configuring git user..."
    & git config --global user.name $UserName
    & git config --global user.email $UserEmail
    
    Write-Success "Git configured: $UserName <$UserEmail>"
}

function Invoke-GitCommit {
    param(
        [string]$Version,
        [string[]]$Files
    )
    
    Write-Info "Staging files for commit..."
    foreach ($file in $Files) {
        if (Test-Path $file) {
            & git add $file
            Write-Info "  Staged: $file"
        }
    }
    
    $commitMessage = "chore(release): bump version to $Version`n`n[skip ci]"
    
    Write-Info "Creating signed commit..."
    & git commit -S -m $commitMessage
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create commit"
    }
    
    Write-Success "Commit created and signed"
}

function New-GitTag {
    param([string]$Version)
    
    $tagName = "v$Version"
    $tagMessage = "Release $Version"
    
    $existingTag = & git tag -l $tagName 2>$null
    if ($existingTag) {
        Write-Warning "Tag $tagName already exists, deleting local tag..."
        & git tag -d $tagName | Out-Null
    }
    
    Write-Info "Creating annotated tag: $tagName"
    & git tag -a -s $tagName -m $tagMessage
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create tag"
    }
    
    Write-Success "Tag created: $tagName"
}

function Publish-ToGitHub {
    param(
        [string]$Remote,
        [string]$Branch,
        [string]$Version
    )
    
    $tagName = "v$Version"
    
    Write-Info "Pushing to $Remote/$Branch..."
    & git push $Remote $Branch
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push commits"
    }
    
    Write-Success "Commits pushed to $Remote/$Branch"
    
    Write-Info "Pushing tag $tagName..."
    & git push $Remote $tagName
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push tag"
    }
    
    Write-Success "Tag pushed: $tagName"
}

#endregion

#region Main Logic

try {
    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No changes will be pushed"
        Write-Host ""
    }
    
    Write-Info "Starting Git publish process..."
    
    if (-not (Test-CommandExists "git")) {
        throw "git is not installed or not in PATH"
    }
    
    Write-Info "Loading secrets from Vault..."
    if (-not (Test-Path $SecretsDir)) {
        throw "Secrets directory not found: $SecretsDir. Make sure Get-VaultSecrets.ps1 ran successfully."
    }
    
    if (-not $SshKeyPath) {
        $SshKeyPath = Join-Path $SecretsDir "ssh_private_key.txt"
    }
    
    if (-not $GpgKey) {
        $GpgKey = Get-VaultSecret -SecretsDir $SecretsDir -SecretName "gpg_private_key"
        if (-not $GpgKey) {
            throw "GPG private key not found in Vault secrets"
        }
    }
    
    if (-not $GpgPassphrase) {
        $GpgPassphrase = Get-VaultSecret -SecretsDir $SecretsDir -SecretName "gpg_passphrase"
    }
    
    if (-not $GitUserName) {
        $GitUserName = Get-VaultSecret -SecretsDir $SecretsDir -SecretName "git_user_name"
    }
    
    if (-not $GitUserEmail) {
        $GitUserEmail = Get-VaultSecret -SecretsDir $SecretsDir -SecretName "git_user_email"
    }
    
    if (-not $Version) {
        if (Test-Path "next-version.txt") {
            $Version = Get-Content "next-version.txt" -Raw
            $Version = $Version.Trim() -replace '^v', ''
            Write-Info "Read version from next-version.txt: $Version"
        } else {
            throw "No version specified and next-version.txt not found"
        }
    }
    
    $Version = $Version -replace '^v', ''
    
    if (-not $Branch) {
        $Branch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            $Branch = "main"
        }
    }
    
    $changedFiles = @("version.tf", "CHANGELOG.md", "README.md")
    if (Test-Path "changed-files.txt") {
        $changedFiles = Get-Content "changed-files.txt" | Where-Object { $_ }
    }
    
    Write-Host ""
    Write-Host "🚀 Publishing Version: $Version" -ForegroundColor Magenta
    Write-Host "   Remote: $RemoteName" -ForegroundColor White
    Write-Host "   Branch: $Branch" -ForegroundColor White
    Write-Host ""
    
    Set-GitConfig -UserName $GitUserName -UserEmail $GitUserEmail
    
    Initialize-SshAgent -KeyPath $SshKeyPath
    
    $gpgKeyId = Initialize-GpgKey -Key $GpgKey -Passphrase $GpgPassphrase
    
    if (-not $DryRun) {
        Invoke-GitCommit -Version $Version -Files $changedFiles
        
        New-GitTag -Version $Version
        
        Publish-ToGitHub -Remote $RemoteName -Branch $Branch -Version $Version
        
        Write-Host ""
        Write-Success "Successfully published version $Version to GitHub!"
        Write-Host ""
        Write-Host "🎉 Release Details:" -ForegroundColor Magenta
        Write-Host "   Version: v$Version" -ForegroundColor Yellow
        Write-Host "   Commit: $(& git rev-parse --short HEAD)" -ForegroundColor White
        Write-Host "   Tag: v$Version" -ForegroundColor White
        Write-Host "   GPG Signed: Yes (Key: $gpgKeyId)" -ForegroundColor Green
        Write-Host ""
        
    } else {
        Write-Host ""
        Write-Warning "DRY RUN - Would have:"
        Write-Host "  1. Committed files: $($changedFiles -join ', ')" -ForegroundColor White
        Write-Host "  2. Created tag: v$Version" -ForegroundColor White
        Write-Host "  3. Pushed to: $RemoteName/$Branch" -ForegroundColor White
        Write-Host "  4. Pushed tag: v$Version" -ForegroundColor White
        Write-Host ""
    }
    
} catch {
    Write-Error "Failed to publish changes: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

#endregion
