function Get-VaultToken {
    <#
    .SYNOPSIS
        Authenticates to Vault using Buildkite JWT token
    
    .DESCRIPTION
        Authenticates to HashiCorp Vault using the JWT token provided by Buildkite.
        Sets the VAULT_TOKEN environment variable for subsequent Vault operations.
    
    .EXAMPLE
        Get-VaultToken
    
    .NOTES
        Requires BUILDKITE_JWT_TOKEN environment variable to be set by Buildkite.
    #>
    
    Write-Host "--- Authenticating to Vault"
    
    if (-not $env:BUILDKITE_JWT_TOKEN) {
        throw "BUILDKITE_JWT_TOKEN environment variable not set"
    }
    
    if (-not $env:VAULT_ADDR) {
        throw "VAULT_ADDR environment variable not set"
    }
    
    $vaultToken = vault write -field=token auth/jwt/login `
        role=buildkite-role `
        jwt="$env:BUILDKITE_JWT_TOKEN"
    
    if ($LASTEXITCODE -ne 0 -or -not $vaultToken) {
        throw "Failed to authenticate to Vault"
    }
    
    $env:VAULT_TOKEN = $vaultToken
    Write-Host "✓ Vault authentication successful"
}
