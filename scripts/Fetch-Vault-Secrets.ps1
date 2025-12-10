#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fetches secrets from HashiCorp Vault for a specific environment
.DESCRIPTION
    Authenticates to Vault and retrieves secrets for various providers:
    - Infrastructure providers (Lynx backend)
    - Cloud providers (AWS, Azure, GCP)
    - Security/monitoring tools (Mondoo, Datadog, etc.)
    - Service providers (ngrok, PagerDuty, etc.)
    
    Automatically discovers all available secrets for an environment and loads them.
.PARAMETER Environment
    The environment to fetch secrets for (dev, tst, prd, etc.)
.PARAMETER Providers
    Optional comma-separated list of specific providers to fetch.
    If not specified, attempts to fetch all known providers.
    Example: "mondoo,aws,ngrok"
.EXAMPLE
    .\fetch-vault-secrets.ps1 -Environment dev
    # Fetches all available secrets for dev
.EXAMPLE
    .\fetch-vault-secrets.ps1 -Environment prd -Providers "mondoo,aws"
    # Fetches only Mondoo and AWS secrets for production
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$Providers
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "🔐 Vault Secret Fetcher"
Write-Host "Environment: $Environment"
Write-Host "========================================"

# Check required environment variables
if (-not $env:VAULT_ADDR) {
    Write-Host "❌ Error: VAULT_ADDR environment variable not set" -ForegroundColor Red
    exit 1
}

#region Vault Authentication

Write-Host ""
Write-Host "--- 🔐 Authenticating to Vault"

# Method 1: AppRole authentication (recommended for CI/CD)
if ($env:VAULT_ROLE_ID -and $env:VAULT_SECRET_ID) {
    Write-Host "Using AppRole authentication..."
    
    $body = @{
        role_id = $env:VAULT_ROLE_ID
        secret_id = $env:VAULT_SECRET_ID
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$env:VAULT_ADDR/v1/auth/approle/login" `
            -Method Post `
            -Body $body `
            -ContentType "application/json"
        
        $env:VAULT_TOKEN = $response.auth.client_token
        Write-Host "✓ Authenticated via AppRole" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error authenticating to Vault: $_" -ForegroundColor Red
        exit 1
    }
}
# Method 2: Token authentication (for local testing)
elseif ($env:VAULT_TOKEN) {
    Write-Host "Using existing VAULT_TOKEN"
    Write-Host "✓ Token authentication" -ForegroundColor Green
}
else {
    Write-Host "❌ Error: No authentication method available" -ForegroundColor Red
    Write-Host "Set one of: VAULT_ROLE_ID+VAULT_SECRET_ID or VAULT_TOKEN" -ForegroundColor Red
    exit 1
}

# Verify Vault connectivity
Write-Host ""
Write-Host "--- 🏥 Verifying Vault connectivity"
try {
    $headers = @{
        "X-Vault-Token" = $env:VAULT_TOKEN
    }
    $response = Invoke-RestMethod -Uri "$env:VAULT_ADDR/v1/sys/health" `
        -Method Get `
        -Headers $headers `
        -ErrorAction SilentlyContinue
    Write-Host "✓ Vault is accessible" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Warning: Could not verify Vault health (this may be normal)" -ForegroundColor Yellow
}

#endregion

#region Helper Functions

function Get-VaultSecret {
    param(
        [string]$Path,
        [string]$Description
    )
    
    try {
        $headers = @{
            "X-Vault-Token" = $env:VAULT_TOKEN
        }
        $uri = "$env:VAULT_ADDR/v1/$Path"
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
        
        if ($response.data.data) {
            Write-Host "  ✓ Retrieved $Description" -ForegroundColor Green
            return $response.data.data
        }
        else {
            Write-Host "  ⚠ No data found at $Path" -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Host "  ⚠ Could not fetch from $Path : $_" -ForegroundColor Yellow
        return $null
    }
}

function Set-EnvironmentVariables {
    param(
        [hashtable]$Secrets,
        [hashtable]$Mapping
    )
    
    foreach ($key in $Mapping.Keys) {
        $envVar = $Mapping[$key]
        if ($Secrets.ContainsKey($key)) {
            Set-Item -Path "env:$envVar" -Value $Secrets[$key]
        }
    }
}

#endregion

#region Provider Configurations

# Define provider configurations
# Each provider has:
# - path: Vault path pattern
# - envVars: Mapping of Vault keys to environment variables
# - required: Whether this provider is required
# - display: How to display values (for security)

$providerConfigs = @{
    
    # Infrastructure Backend
    "lynx" = @{
        path = "secret/data/lynx/$Environment"
        description = "Lynx backend credentials"
        required = $true
        envVars = @{
            username = "LYNX_USERNAME"
            password = "LYNX_PASSWORD"
        }
        display = @{
            username = { param($v) $v }
            password = { "********" }
        }
    }
    
    # Security & Compliance
    "mondoo" = @{
        path = "secret/data/mondoo/$Environment"
        description = "Mondoo security platform"
        required = $false
        envVars = @{
            token = "TF_VAR_mondoo_token"
            space_id = "TF_VAR_mondoo_space_id"
        }
        display = @{
            token = { param($v) "$($v.Substring(0, [Math]::Min(20, $v.Length)))..." }
            space_id = { param($v) $v }
        }
    }
    
    # Cloud Providers
    "aws" = @{
        path = "secret/data/aws/$Environment"
        description = "AWS credentials"
        required = $false
        envVars = @{
            access_key_id = "AWS_ACCESS_KEY_ID"
            secret_access_key = "AWS_SECRET_ACCESS_KEY"
            region = "AWS_REGION"
            session_token = "AWS_SESSION_TOKEN"
        }
        display = @{
            access_key_id = { param($v) "$($v.Substring(0, [Math]::Min(10, $v.Length)))..." }
            secret_access_key = { "********" }
            region = { param($v) $v }
            session_token = { "********" }
        }
    }
    
    "azure" = @{
        path = "secret/data/azure/$Environment"
        description = "Azure credentials"
        required = $false
        envVars = @{
            client_id = "ARM_CLIENT_ID"
            client_secret = "ARM_CLIENT_SECRET"
            tenant_id = "ARM_TENANT_ID"
            subscription_id = "ARM_SUBSCRIPTION_ID"
        }
        display = @{
            client_id = { param($v) $v }
            client_secret = { "********" }
            tenant_id = { param($v) $v }
            subscription_id = { param($v) $v }
        }
    }
    
    "gcp" = @{
        path = "secret/data/gcp/$Environment"
        description = "GCP credentials"
        required = $false
        envVars = @{
            credentials_json = "GOOGLE_CREDENTIALS"
            project_id = "GOOGLE_PROJECT"
        }
        display = @{
            credentials_json = { "[JSON credentials]" }
            project_id = { param($v) $v }
        }
    }
    
    # Networking & Tunneling
    "ngrok" = @{
        path = "secret/data/ngrok/$Environment"
        description = "ngrok tunneling service"
        required = $false
        envVars = @{
            auth_token = "NGROK_AUTH_TOKEN"
            api_key = "NGROK_API_KEY"
            domain = "NGROK_DOMAIN"
        }
        display = @{
            auth_token = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            api_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            domain = { param($v) $v }
        }
    }
    
    # Monitoring & Observability
    "datadog" = @{
        path = "secret/data/datadog/$Environment"
        description = "Datadog monitoring"
        required = $false
        envVars = @{
            api_key = "DD_API_KEY"
            app_key = "DD_APP_KEY"
            site = "DD_SITE"
        }
        display = @{
            api_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            app_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            site = { param($v) $v }
        }
    }
    
    "newrelic" = @{
        path = "secret/data/newrelic/$Environment"
        description = "New Relic monitoring"
        required = $false
        envVars = @{
            api_key = "NEW_RELIC_API_KEY"
            license_key = "NEW_RELIC_LICENSE_KEY"
            account_id = "NEW_RELIC_ACCOUNT_ID"
        }
        display = @{
            api_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            license_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            account_id = { param($v) $v }
        }
    }
    
    # Alerting & Incident Management
    "pagerduty" = @{
        path = "secret/data/pagerduty/$Environment"
        description = "PagerDuty incident management"
        required = $false
        envVars = @{
            api_token = "PAGERDUTY_TOKEN"
            integration_key = "PAGERDUTY_INTEGRATION_KEY"
        }
        display = @{
            api_token = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
            integration_key = { param($v) "$($v.Substring(0, [Math]::Min(15, $v.Length)))..." }
        }
    }
    
    # Container Registries
    "dockerhub" = @{
        path = "secret/data/dockerhub/$Environment"
        description = "Docker Hub registry"
        required = $false
        envVars = @{
            username = "DOCKER_USERNAME"
            password = "DOCKER_PASSWORD"
            registry = "DOCKER_REGISTRY"
        }
        display = @{
            username = { param($v) $v }
            password = { "********" }
            registry = { param($v) $v }
        }
    }
    
    "ecr" = @{
        path = "secret/data/ecr/$Environment"
        description = "AWS ECR registry"
        required = $false
        envVars = @{
            registry_url = "ECR_REGISTRY_URL"
            region = "ECR_REGION"
        }
        display = @{
            registry_url = { param($v) $v }
            region = { param($v) $v }
        }
    }
    
    # Secrets Management (for app secrets)
    "app-secrets" = @{
        path = "secret/data/app/$Environment"
        description = "Application secrets"
        required = $false
        envVars = @{
            database_url = "DATABASE_URL"
            redis_url = "REDIS_URL"
            api_key = "APP_API_KEY"
            secret_key = "APP_SECRET_KEY"
        }
        display = @{
            database_url = { param($v) 
                if ($v -match "^(.+?)://(.+?):(.+?)@(.+)$") {
                    "$($Matches[1])://***:***@$($Matches[4])"
                } else { "***" }
            }
            redis_url = { param($v) 
                if ($v -match "^(.+?)://(.+)$") {
                    "$($Matches[1])://***"
                } else { "***" }
            }
            api_key = { "********" }
            secret_key = { "********" }
        }
    }
    
    # Git Credentials
    "github" = @{
        path = "secret/data/github/$Environment"
        description = "GitHub access"
        required = $false
        envVars = @{
            token = "GITHUB_TOKEN"
            app_id = "GITHUB_APP_ID"
            private_key = "GITHUB_PRIVATE_KEY"
        }
        display = @{
            token = { param($v) "$($v.Substring(0, [Math]::Min(10, $v.Length)))..." }
            app_id = { param($v) $v }
            private_key = { "[Private Key]" }
        }
    }
    
    "gitlab" = @{
        path = "secret/data/gitlab/$Environment"
        description = "GitLab access"
        required = $false
        envVars = @{
            token = "GITLAB_TOKEN"
            url = "GITLAB_URL"
        }
        display = @{
            token = { param($v) "$($v.Substring(0, [Math]::Min(10, $v.Length)))..." }
            url = { param($v) $v }
        }
    }
}

#endregion

#region Fetch Secrets

# Determine which providers to fetch
$providersToFetch = if ($Providers) {
    $Providers -split ',' | ForEach-Object { $_.Trim() }
} else {
    $providerConfigs.Keys
}

Write-Host ""
Write-Host "--- 🔑 Fetching secrets for providers: $($providersToFetch -join ', ')"
Write-Host ""

# Track loaded secrets
$loadedProviders = @()
$failedRequired = @()
$secretsForExport = @()

foreach ($providerName in $providersToFetch) {
    if (-not $providerConfigs.ContainsKey($providerName)) {
        Write-Host "⚠ Unknown provider: $providerName" -ForegroundColor Yellow
        continue
    }
    
    $config = $providerConfigs[$providerName]
    
    Write-Host "Fetching $($config.description)..."
    $secrets = Get-VaultSecret -Path $config.path -Description $config.description
    
    if ($secrets) {
        # Set environment variables
        foreach ($vaultKey in $config.envVars.Keys) {
            $envVar = $config.envVars[$vaultKey]
            
            if ($secrets.ContainsKey($vaultKey) -and $secrets[$vaultKey]) {
                Set-Item -Path "env:$envVar" -Value $secrets[$vaultKey]
                
                # Display value (masked if needed)
                $displayValue = if ($config.display.ContainsKey($vaultKey)) {
                    & $config.display[$vaultKey] $secrets[$vaultKey]
                } else {
                    "***"
                }
                
                Write-Host "  $vaultKey → $envVar = $displayValue" -ForegroundColor Gray
                
                # Store for export
                $secretsForExport += @{
                    envVar = $envVar
                    value = $secrets[$vaultKey]
                }
            }
        }
        
        $loadedProviders += $providerName
        Write-Host ""
    }
    elseif ($config.required) {
        Write-Host "❌ Required provider '$providerName' not found!" -ForegroundColor Red
        $failedRequired += $providerName
    }
    else {
        Write-Host "  ℹ Optional provider not configured" -ForegroundColor Cyan
        Write-Host ""
    }
}

# Check if required providers failed
if ($failedRequired.Count -gt 0) {
    Write-Host ""
    Write-Host "❌ Error: Required providers not found: $($failedRequired -join ', ')" -ForegroundColor Red
    exit 1
}

#endregion

#region Export Secrets

Write-Host ""
Write-Host "--- 💾 Exporting secrets to file"
$secretsFile = "$env:TEMP\vault-secrets-$Environment.ps1"

# Build export file content
$secretsContent = @"
# Environment secrets for $Environment
# Generated at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
# Loaded providers: $($loadedProviders -join ', ')

"@

# Add all environment variables
foreach ($secret in $secretsForExport) {
    $secretsContent += "`$env:$($secret.envVar) = '$($secret.value)'`n"
}

$secretsContent += @"

Write-Host "✓ Loaded secrets for $Environment" -ForegroundColor Green
Write-Host "  Providers: $($loadedProviders -join ', ')" -ForegroundColor Gray
"@

$secretsContent | Out-File -FilePath $secretsFile -Encoding UTF8
Write-Host "✓ Secrets exported to $secretsFile" -ForegroundColor Green

#endregion

#region Summary

Write-Host ""
Write-Host "========================================"
Write-Host "✓ Secrets Ready" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
Write-Host "Loaded providers ($($loadedProviders.Count)):"
foreach ($provider in $loadedProviders) {
    Write-Host "  ✓ $provider" -ForegroundColor Green
}

if ($loadedProviders.Count -eq 0) {
    Write-Host "  ⚠ No providers loaded" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Export file: $secretsFile"
Write-Host ""
Write-Host "To use in Buildkite:"
Write-Host "  buildkite-agent artifact upload $secretsFile"
Write-Host "  # In next step:"
Write-Host "  buildkite-agent artifact download $secretsFile ."
Write-Host "  . $secretsFile"

#endregion
