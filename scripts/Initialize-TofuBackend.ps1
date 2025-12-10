function Initialize-TofuBackend {
    <#
    .SYNOPSIS
        Initializes OpenTofu backend with Clivern Lynx HTTP backend
    
    .DESCRIPTION
        Configures and initializes OpenTofu to use Clivern Lynx as an HTTP backend
        for state storage. Supports distributed locking via Lynx's REST API.
    
    .PARAMETER EnvironmentName
        Target environment (dev, stg, prd)
    
    .PARAMETER ProjectName
        Project name used in state path
    
    .PARAMETER LynxBaseUrl
        Base URL of the Lynx server (default: uses $env:LYNX_BASE_URL or https://lynx.company.com)
    
    .EXAMPLE
        Initialize-TofuBackend -EnvironmentName "dev" -ProjectName "terraform-mondoo"
    
    .EXAMPLE
        Initialize-TofuBackend -EnvironmentName "prd" -ProjectName "terraform-mondoo" -LynxBaseUrl "https://lynx-eu.company.com"
    
    .NOTES
        Requires Get-EnvironmentCredentials to be called first.
        Sets environment variables for HTTP backend authentication:
        - TF_HTTP_USERNAME
        - TF_HTTP_PASSWORD
        - TF_HTTP_LOCK_USERNAME
        - TF_HTTP_LOCK_PASSWORD
        - TF_HTTP_UNLOCK_USERNAME
        - TF_HTTP_UNLOCK_PASSWORD
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$LynxBaseUrl = $env:LYNX_BASE_URL
    )
    
    # Default to standard URL if not provided
    if (-not $LynxBaseUrl) {
        $LynxBaseUrl = "https://lynx.company.com"
        Write-Host "Using default Lynx URL: $LynxBaseUrl"
    }
    
    Write-Host "--- Initializing OpenTofu backend for $EnvironmentName"
    
    # Validate Lynx credentials are set
    if (-not $env:LYNX_USERNAME) {
        throw "LYNX_USERNAME environment variable not set. Call Get-EnvironmentCredentials first."
    }
    
    if (-not $env:LYNX_PASSWORD) {
        throw "LYNX_PASSWORD environment variable not set. Call Get-EnvironmentCredentials first."
    }
    
    # Construct Lynx API URLs
    $statePath = "$ProjectName/$EnvironmentName"
    $stateUrl = "$LynxBaseUrl/api/state/$statePath"
    $lockUrl = "$LynxBaseUrl/api/state/$statePath/lock"
    $unlockUrl = "$LynxBaseUrl/api/state/$statePath/lock"
    
    Write-Host "  Lynx State URL: $stateUrl"
    Write-Host "  Lock URL: $lockUrl"
    Write-Host "  Username: $env:LYNX_USERNAME"
    
    # Set HTTP backend authentication via environment variables
    # OpenTofu/Terraform HTTP backend automatically uses these
    $env:TF_HTTP_USERNAME = $env:LYNX_USERNAME
    $env:TF_HTTP_PASSWORD = $env:LYNX_PASSWORD
    $env:TF_HTTP_LOCK_USERNAME = $env:LYNX_USERNAME
    $env:TF_HTTP_LOCK_PASSWORD = $env:LYNX_PASSWORD
    $env:TF_HTTP_UNLOCK_USERNAME = $env:LYNX_USERNAME
    $env:TF_HTTP_UNLOCK_PASSWORD = $env:LYNX_PASSWORD
    
    try {
        # Test Lynx connectivity before initializing
        Write-Host "--- Testing Lynx connectivity"
        
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String(
                [Text.Encoding]::ASCII.GetBytes("${env:LYNX_USERNAME}:${env:LYNX_PASSWORD}")
            )
        }
        
        try {
            $response = Invoke-WebRequest -Uri $stateUrl -Method Get -Headers $headers -ErrorAction SilentlyContinue
            Write-Host "✓ Lynx connectivity verified (state exists)"
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                Write-Host "✓ Lynx connectivity verified (new state - will be created)"
            } elseif ($_.Exception.Response.StatusCode.value__ -eq 401) {
                throw "Lynx authentication failed. Check credentials."
            } else {
                Write-Warning "Lynx connectivity test returned: $($_.Exception.Message)"
                Write-Host "Proceeding with initialization anyway..."
            }
        }
        
        # Initialize OpenTofu with HTTP backend configuration
        Write-Host "--- Initializing OpenTofu with Lynx backend"
        
        tofu init `
            -backend-config="address=$stateUrl" `
            -backend-config="lock_address=$lockUrl" `
            -backend-config="unlock_address=$unlockUrl" `
            -backend-config="lock_method=POST" `
            -backend-config="unlock_method=DELETE" `
            -backend-config="skip_cert_verification=false" `
            -reconfigure
        
        if ($LASTEXITCODE -ne 0) {
            throw "OpenTofu init failed for $EnvironmentName"
        }
        
        Write-Host "✓ Backend initialized successfully"
        
        # Verify backend configuration
        Write-Host "--- Verifying backend configuration"
        tofu providers
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Backend verification successful"
        }
        
    } catch {
        Write-Error "Failed to initialize Lynx backend: $_"
        Write-Host ""
        Write-Host "Troubleshooting steps:"
        Write-Host "1. Verify Lynx server is accessible: $LynxBaseUrl"
        Write-Host "2. Check credentials are correct"
        Write-Host "3. Verify LYNX_USERNAME and LYNX_PASSWORD are set"
        Write-Host "4. Ensure Lynx has the state path configured"
        Write-Host "5. Review Lynx server logs for errors"
        throw
    }
}
