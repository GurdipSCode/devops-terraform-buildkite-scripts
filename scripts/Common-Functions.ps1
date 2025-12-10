# scripts/common-functions.ps1
# Common functions for Terraform/OpenTofu operations with Clivern Lynx backend

$ErrorActionPreference = "Stop"

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

function Set-ProjectContext {
    <#
    .SYNOPSIS
        Sets Terraform variables for project context
    
    .DESCRIPTION
        Sets Terraform environment variables for project identification.
        These variables are used for tagging and resource naming.
    
    .PARAMETER ProjectName
        Project name (required)
    
    .PARAMETER ServiceName
        Service name (optional, defaults to $env:SERVICE_NAME)
    
    .EXAMPLE
        Set-ProjectContext -ProjectName "terraform-mondoo"
    
    .EXAMPLE
        Set-ProjectContext -ProjectName "infrastructure" -ServiceName "networking"
    
    .NOTES
        Sets environment variables:
        - TF_VAR_project_name
        - TF_VAR_service_name
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,
        
        [Parameter(Mandatory=$false)]
        [string]$ServiceName = $env:SERVICE_NAME
    )
    
    Write-Host "--- Setting project context"
    $env:TF_VAR_project_name = $ProjectName
    $env:TF_VAR_service_name = $ServiceName
    
    Write-Host "  Project: $ProjectName"
    Write-Host "  Service: $ServiceName"
}

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

function Backup-TerraformState {
    <#
    .SYNOPSIS
        Creates a timestamped backup of the current Terraform state
    
    .DESCRIPTION
        Pulls the current state from Lynx backend and creates a local backup
        with timestamp. Uploads the backup to Buildkite artifacts for retention.
    
    .PARAMETER EnvironmentName
        Environment identifier for backup naming
    
    .EXAMPLE
        $backup = Backup-TerraformState -EnvironmentName "prd"
        if ($backup) {
            Write-Host "Backup created at: $backup"
        }
    
    .OUTPUTS
        String - Path to backup file if successful
        $null - If backup fails (non-blocking)
    
    .NOTES
        Non-blocking: Returns $null on failure instead of throwing.
        Useful for disaster recovery and rollback scenarios.
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName
    )
    
    Write-Host "--- Creating state backup for $EnvironmentName"
    
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = "backups"
    $backupPath = "$backupDir/$EnvironmentName-$timestamp.tfstate"
    
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    
    try {
        tofu state pull | Out-File -FilePath $backupPath -Encoding utf8
        
        if (Test-Path $backupPath) {
            $size = (Get-Item $backupPath).Length
            Write-Host "✓ Backup created: $backupPath ($size bytes)"
            
            buildkite-agent artifact upload $backupPath
            Write-Host "✓ Backup uploaded to Buildkite artifacts"
            
            return $backupPath
        } else {
            throw "Backup file was not created"
        }
    } catch {
        Write-Warning "Failed to create state backup: $_"
        return $null
    }
}

function Test-StateLock {
    <#
    .SYNOPSIS
        Checks for Terraform state locks and optionally force-unlocks
    
    .DESCRIPTION
        Checks if the Terraform state is locked in Lynx backend.
        Can automatically force-unlock if FORCE_UNLOCK environment variable is set to "true".
    
    .EXAMPLE
        Test-StateLock
    
    .EXAMPLE
        $env:FORCE_UNLOCK = "true"
        Test-StateLock
    
    .NOTES
        Environment Variables:
        - FORCE_UNLOCK: Set to "true" to automatically unlock locked states
        
        WARNING: Force unlocking can cause state corruption if another
        operation is legitimately running. Use with caution.
    #>
    
    Write-Host "--- Checking for state locks"
    
    $lockOutput = tofu force-unlock -list 2>&1
    
    if ($lockOutput -match "Lock Info") {
        Write-Host "⚠️  State is locked!"
        Write-Host $lockOutput
        
        if ($env:FORCE_UNLOCK -eq "true") {
            Write-Host "FORCE_UNLOCK enabled - attempting to unlock..."
            
            # Extract lock ID from output
            if ($lockOutput -match "ID:\s+(.+)") {
                $lockId = $matches[1].Trim()
                Write-Host "Unlocking with ID: $lockId"
                tofu force-unlock -force $lockId
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ State unlocked successfully"
                } else {
                    throw "Failed to force unlock state"
                }
            } else {
                throw "Could not extract lock ID from output"
            }
        } else {
            throw "State is locked. Set FORCE_UNLOCK=true to override, or wait for lock to clear."
        }
    } else {
        Write-Host "✓ No state locks detected"
    }
}

function Plan-Environment {
    <#
    .SYNOPSIS
        Plans Terraform changes for an environment
    
    .DESCRIPTION
        Complete planning workflow including:
        - Vault authentication
        - Credential retrieval
        - Backend initialization
        - Lock checking
        - Configuration validation
        - Plan generation
        - Plan analysis
        - Artifact upload
        - Buildkite annotations
    
    .PARAMETER EnvironmentName
        Target environment (dev, stg, prd)
    
    .PARAMETER ProjectName
        Project name for context and state path
    
    .EXAMPLE
        Plan-Environment -EnvironmentName "dev" -ProjectName "terraform-mondoo"
    
    .EXAMPLE
        Plan-Environment -EnvironmentName "prd" -ProjectName "terraform-mondoo"
    
    .NOTES
        Generates artifacts:
        - tfplan-{env}: Binary plan file
        - tfplan-{env}.json: JSON plan for analysis
        - plan-summary-{env}.txt: Human-readable summary
        
        Sets Buildkite metadata:
        - plan-{env}-add: Resources to add
        - plan-{env}-change: Resources to change
        - plan-{env}-destroy: Resources to destroy
    #>
    
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName
    )
    
    $step_start = Get-Date
    
    try {
        Write-Host "╔════════════════════════════════════════════════════════════════╗"
        Write-Host "║  PLAN: $EnvironmentName".PadRight(64) + "║"
        Write-Host "╚════════════════════════════════════════════════════════════════╝"
        
        # Authenticate and setup
        Get-VaultToken
        Get-EnvironmentCredentials -EnvironmentName $EnvironmentName
        Set-ProjectContext -ProjectName $ProjectName
        
        # Change to environment directory if it exists
        $envPath = if (Test-Path $EnvironmentName -PathType Container) { $EnvironmentName } else { "." }
        Push-Location $envPath
        
        try {
            # Initialize Lynx backend
            Initialize-TofuBackend -EnvironmentName $EnvironmentName -ProjectName $ProjectName
            
            # Check for state locks
            Test-StateLock
            
            # Validate configuration
            Write-Host "--- Validating Terraform configuration"
            tofu validate
            
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform validation failed"
            }
            
            Write-Host "✓ Configuration is valid"
            
            # Run plan
            Write-Host "--- Running Terraform plan"
            $planFile = "tfplan-$EnvironmentName"
            $planJson = "tfplan-$EnvironmentName.json"
            $planSummary = "plan-summary-$EnvironmentName.txt"
            
            tofu plan -out=$planFile | Tee-Object -FilePath $planSummary
            
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform plan failed"
            }
            
            # Generate JSON for analysis
            Write-Host "--- Generating plan JSON"
            tofu show -json $planFile | Out-File -FilePath $planJson -Encoding utf8
            
            # Analyze plan with Fabric AI (if available)
            Write-Host ""
            if (Test-Path ".\scripts\Invoke-FabricAnalysis.ps1") {
                try {
                    .\scripts\Invoke-FabricAnalysis.ps1 `
                        -PlanSummaryPath $planSummary `
                        -OutputPath "fabric-analysis-$EnvironmentName.txt" `
                        -ErrorAction SilentlyContinue
                    
                    # Upload Fabric analysis as artifact if generated
                    if (Test-Path "fabric-analysis-$EnvironmentName.txt") {
                        buildkite-agent artifact upload "fabric-analysis-$EnvironmentName.txt"
                        Write-Host "✓ Fabric analysis uploaded to artifacts"
                    }
                } catch {
                    Write-Warning "Fabric analysis encountered an issue: $($_.Exception.Message)"
                    Write-Host "Continuing with plan..."
                }
            } else {
                Write-Host "ℹ️  Fabric analysis script not found (optional)"
            }
            
            # Analyze plan with Overmind (if available)
            Write-Host ""
            if (Test-Path ".\scripts\Invoke-OvermindAnalysis.ps1") {
                try {
                    .\scripts\Invoke-OvermindAnalysis.ps1 `
                        -PlanJsonPath $planJson `
                        -OutputPath "overmind-analysis-$EnvironmentName.txt" `
                        -IncludeBlastRadius `
                        -ErrorAction SilentlyContinue
                    
                    # Upload Overmind analysis as artifact if generated
                    if (Test-Path "overmind-analysis-$EnvironmentName.txt") {
                        buildkite-agent artifact upload "overmind-analysis-$EnvironmentName.txt"
                        Write-Host "✓ Overmind analysis uploaded to artifacts"
                    }
                } catch {
                    Write-Warning "Overmind analysis encountered an issue: $($_.Exception.Message)"
                    Write-Host "Continuing with plan..."
                }
            } else {
                Write-Host "ℹ️  Overmind analysis script not found (optional)"
            }
            
            # Parse plan statistics
            Write-Host "--- Plan Summary"
            $planContent = Get-Content $planSummary -Raw
            
            if ($planContent -match "Plan: (\d+) to add, (\d+) to change, (\d+) to destroy") {
                $toAdd = $matches[1]
                $toChange = $matches[2]
                $toDestroy = $matches[3]
                
                Write-Host "  Resources to add: $toAdd"
                Write-Host "  Resources to change: $toChange"
                Write-Host "  Resources to destroy: $toDestroy"
                
                # Store in Buildkite metadata
                buildkite-agent meta-data set "plan-$EnvironmentName-add" $toAdd
                buildkite-agent meta-data set "plan-$EnvironmentName-change" $toChange
                buildkite-agent meta-data set "plan-$EnvironmentName-destroy" $toDestroy
                
                # Create Buildkite annotation
                if ([int]$toDestroy -gt 0) {
                    buildkite-agent annotate --style warning --context "plan-$EnvironmentName" @"
:warning: **$EnvironmentName Plan**: $toDestroy resource(s) will be destroyed
- Add: $toAdd
- Change: $toChange  
- Destroy: $toDestroy

Review carefully before applying!
"@
                } else {
                    buildkite-agent annotate --style success --context "plan-$EnvironmentName" @"
:white_check_mark: **$EnvironmentName Plan Complete**
- Add: $toAdd resources
- Change: $toChange resources
- Destroy: $toDestroy resources
"@
                }
            } elseif ($planContent -match "No changes") {
                Write-Host "  No changes detected"
                buildkite-agent annotate --style success --context "plan-$EnvironmentName" @"
:white_check_mark: **$EnvironmentName**: No changes needed
Infrastructure is up to date.
"@
            }
            
            Write-Host "✓ Plan completed successfully"
            
        } finally {
            Pop-Location
        }
        
    } catch {
        Write-Host "╔════════════════════════════════════════════════════════════════╗"
        Write-Host "║  ERROR: Plan Failed".PadRight(64) + "║"
        Write-Host "╚════════════════════════════════════════════════════════════════╝"
        Write-Host "Error: $($_.Exception.Message)"
        Write-Host "Location: $($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine)"
        Write-Host "Stack Trace:"
        Write-Host $_.ScriptStackTrace
        throw
    } finally {
        $duration = (Get-Date) - $step_start
        Write-Host "--- Duration: $($duration.TotalSeconds) seconds"
    }
}

function Apply-Environment {
    <#
    .SYNOPSIS
        Applies Terraform changes to an environment
    
    .DESCRIPTION
        Complete apply workflow including:
        - Vault authentication
        - Credential retrieval
        - Plan artifact download
        - Backend initialization
        - Lock checking
        - State backup
        - Plan application
        - Output generation
        - Artifact upload
        - Notifications
    
    .PARAMETER EnvironmentName
        Target environment (dev, stg, prd)
    
    .PARAMETER ProjectName
        Project name for context and state path
    
    .EXAMPLE
        Apply-Environment -EnvironmentName "dev" -ProjectName "terraform-mondoo"
    
    .EXAMPLE
        Apply-Environment -EnvironmentName "prd" -ProjectName "terraform-mondoo"
    
    .NOTES
        Prerequisites:
        - Plan-Environment must have been run successfully
        - Plan artifacts must be available in Buildkite
        
        Generates artifacts:
        - outputs-{env}.json: Terraform outputs
        - apply-summary-{env}.txt: Apply summary
