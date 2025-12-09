function Get-EnvironmentCredentials {
    <#
    .SYNOPSIS
        Retrieves environment-specific credentials from Vault
    
    .DESCRIPTION
        Retrieves Mondoo API token and Lynx HTTP backend credentials from Vault.
        Supports environment-specific credentials with fallback to default credentials.
    
    .PARAMETER EnvironmentName
        Environment name (dev, stg, prd)
    
    .EXAMPLE
        Get-EnvironmentCredentials -EnvironmentName "prd"
    
    .EXAMPLE
        Get-EnvironmentCredentials -EnvironmentName "dev"
    
    .NOTES
        Requires Get-VaultToken to be called first.
        Sets environment variables:
        - TF_VAR_mondoo_service_account_token
        - LYNX_USERNAME
        - LYNX_PASSWORD
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName
    )
    
    Write-Host "--- Retrieving credentials for $EnvironmentName"
    
    if (-not $env:VAULT_TOKEN) {
        throw "VAULT_TOKEN not set. Call Get-VaultToken first."
    }
    
    # Get Mondoo credentials
    Write-Host "Retrieving Mondoo token..."
    try {
        $env:TF_VAR_mondoo_service_account_token = vault kv get `
            -namespace=$env:VAULT_NAMESPACE `
            -field=token `
            secret/data/mondoo
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve Mondoo token"
        }
    } catch {
        throw "Failed to retrieve Mondoo credentials: $_"
    }
    
    # Try environment-specific Lynx credentials first
    Write-Host "Checking for $EnvironmentName-specific Lynx credentials..."
    $envUsername = vault kv get -field=username "secret/lynx/terraform-$EnvironmentName" 2>$null
    $envPassword = vault kv get -field=password "secret/lynx/terraform-$EnvironmentName" 2>$null
    
    if ($envUsername -and $envPassword -and $LASTEXITCODE -eq 0) {
        Write-Host "✓ Using $EnvironmentName-specific Lynx credentials"
        $env:LYNX_USERNAME = $envUsername
        $env:LYNX_PASSWORD = $envPassword
    } else {
        Write-Host "Using default Lynx credentials"
        $env:LYNX_USERNAME = vault kv get -field=username secret/lynx/terraform
        $env:LYNX_PASSWORD = vault kv get -field=password secret/lynx/terraform
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve Lynx credentials"
        }
    }
    
    Write-Host "✓ Credentials retrieved successfully"
}
