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
            
            # Analyze plan with fabric (if available)
            if (Get-Command fabric -ErrorAction SilentlyContinue) {
                Write-Host "--- Analyzing plan with Fabric"
                Get-Content $planSummary | fabric --pattern analyze_terraform_plan
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
        - backups/{env}-{timestamp}.tfstate: Pre-apply state backup
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
        Write-Host "║  APPLY: $EnvironmentName".PadRight(64) + "║"
        Write-Host "╚════════════════════════════════════════════════════════════════╝"
        
        # Authenticate and setup
        Get-VaultToken
        Get-EnvironmentCredentials -EnvironmentName $EnvironmentName
        Set-ProjectContext -ProjectName $ProjectName
        
        # Change to environment directory if it exists
        $envPath = if (Test-Path $EnvironmentName -PathType Container) { $EnvironmentName } else { "." }
        Push-Location $envPath
        
        try {
            # Download plan artifacts from Buildkite
            Write-Host "--- Downloading plan artifacts"
            $planFile = "tfplan-$EnvironmentName"
            $planJson = "tfplan-$EnvironmentName.json"
            
            buildkite-agent artifact download $planFile .
            buildkite-agent artifact download $planJson .
            
            # Verify plan file exists
            if (-not (Test-Path $planFile)) {
                throw "Plan file $planFile not found. Did validation step complete successfully?"
            }
            
            Write-Host "✓ Downloaded: $planFile"
            Write-Host "✓ Downloaded: $planJson"
            
            # Initialize Lynx backend
            Initialize-TofuBackend -EnvironmentName $EnvironmentName -ProjectName $ProjectName
            
            # Check for state locks
            Test-StateLock
            
            # Backup current state before applying
            $backup = Backup-TerraformState -EnvironmentName $EnvironmentName
            if ($backup) {
                Write-Host "✓ State backed up: $backup"
            } else {
                Write-Warning "State backup failed, but continuing with apply"
            }
            
            # Apply the plan
            Write-Host "--- Applying Terraform plan"
            tofu apply -auto-approve $planFile | Tee-Object -FilePath "apply-summary-$EnvironmentName.txt"
            
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform apply failed"
            }
            
            # Generate outputs
            Write-Host "--- Generating apply outputs"
            tofu output -json | Out-File -FilePath "outputs-$EnvironmentName.json" -Encoding utf8
            
            # Upload artifacts
            Write-Host "--- Uploading apply outputs"
            buildkite-agent artifact upload "outputs-$EnvironmentName.json"
            buildkite-agent artifact upload "apply-summary-$EnvironmentName.txt"
            
            Write-Host "✓ Apply completed successfully"
            
            # Production notification
            if ($EnvironmentName -match "prod|production|prd") {
                Write-Host "🚀 Production deployment completed for $EnvironmentName"
                
                # Create success annotation
                buildkite-agent annotate --style success --context "apply-$EnvironmentName" @"
:rocket: **Production Deployment Complete**

Environment: $EnvironmentName
Project: $ProjectName
Status: Success
"@
            }
            
        } finally {
            Pop-Location
        }
        
    } catch {
        Write-Host "╔════════════════════════════════════════════════════════════════╗"
        Write-Host "║  ERROR: Apply Failed".PadRight(64) + "║"
        Write-Host "╚════════════════════════════════════════════════════════════════╝"
        Write-Host "Error: $($_.Exception.Message)"
        Write-Host "Location: $($_.InvocationInfo.ScriptLineNumber):$($_.InvocationInfo.OffsetInLine)"
        Write-Host "Stack Trace:"
        Write-Host $_.ScriptStackTrace
        
        # Create error annotation
        buildkite-agent annotate --style error --context "apply-$EnvironmentName" @"
:x: **Apply Failed for $EnvironmentName**

Error: $($_.Exception.Message)

Check the build logs for details.
"@
        
        throw
    } finally {
        $duration = (Get-Date) - $step_start
        Write-Host "--- Duration: $($duration.TotalSeconds) seconds"
    }
}
