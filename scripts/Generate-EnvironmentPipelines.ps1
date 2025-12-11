# scripts/Generate-EnvironmentPipelines.ps1
<#
.SYNOPSIS
    Generates dynamic Buildkite pipeline for each environment

.DESCRIPTION
    Discovers environment directories and generates a dynamic pipeline
    with plan, approve, and apply steps for each environment.
#>

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "  Dynamic Pipeline Generation"
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host ""

# Validate common-functions.ps1 exists
if (-not (Test-Path ".\scripts\common-functions.ps1")) {
    throw "common-functions.ps1 not found in scripts/ directory"
}

# Parse target environments from configuration
$targetEnvs = $env:TARGET_ENVIRONMENTS -split "," | ForEach-Object { $_.Trim() }
Write-Host "Target environments: $($targetEnvs -join ', ')"

# Discover environment directories
Write-Host "--- Discovering environment directories"
$envDirs = Get-ChildItem -Directory | Where-Object { 
    $name = $_.Name.ToLower()
    $name -match "^(dev|tst|stg|prd)" -or $name -match "-(dev|tst|stg|prd)$"
}

if ($envDirs.Count -eq 0) {
    Write-Host "⚠️  No environment directories found"
    Write-Host "Using root directory as single environment"
    $envDirs = @(@{Name = "default"; FullName = "."})
} else {
    Write-Host "Found directories: $($envDirs.Name -join ', ')"
}

# Filter to only target environments
if ($targetEnvs -and $targetEnvs.Count -gt 0) {
    $envDirs = $envDirs | Where-Object { $targetEnvs -contains $_.Name }
    Write-Host "Filtered to targets: $($envDirs.Name -join ', ')"
}

if ($envDirs.Count -eq 0) {
    throw "No matching environment directories found for: $($targetEnvs -join ', ')"
}

# Store environment list in metadata
$envList = $envDirs.Name -join ","
buildkite-agent meta-data set "environments" $envList
Write-Host ""

# Generate dynamic pipeline
Write-Host "--- Generating pipeline YAML"
$pipeline = @"
steps:
"@

foreach ($env in $envDirs) {
    $envName = $env.Name
    $envNameSafe = $envName -replace "[^a-zA-Z0-9]", "-"
    
    Write-Host "Adding steps for: $envName"
    
    $pipeline += @"

  - group: ":rocket: $envName Environment"
    key: "env-$envNameSafe"
    steps:
      
      - label: ":mag: $envName - Plan"
        key: "plan-$envNameSafe"
        command: "powershell -File .\\scripts\\Plan-TerraformEnvironment.ps1 -EnvironmentName `"$envName`""
        artifact_paths:
          - "$envName/tfplan-$envName"
          - "$envName/tfplan-$envName.json"
          - "$envName/plan-summary-$envName.txt"
          - "$envName/fabric-analysis-$envName.txt"
          - "$envName/overmind-analysis-$envName.txt"
        agents:
          queue: "windows"
        env:
          ENVIRONMENT_NAME: "$envName"
"@
    
    # Add approval block
    if ($env:REQUIRE_APPROVAL -eq "true" -or $envName -match "prd|prod|production") {
        $pipeline += @"

      - block: ":warning: Approve $envName Deployment"
        key: "approve-$envNameSafe"
        depends_on: "plan-$envNameSafe"
        prompt: "Review the Terraform plan and approve deployment to $envName"
        fields:
          - text: "Deployment Notes"
            key: "deployment-notes-$envNameSafe"
            hint: "Optional notes about this deployment"
            required: false
          - text: "Approved By"
            key: "approved-by-$envNameSafe"
            hint: "Your name"
            required: true
        if: build.branch == "main"
"@
    }
    
    $dependsOn = if ($env:REQUIRE_APPROVAL -eq "true" -or $envName -match "prd|prod|production") { 
        "approve-$envNameSafe" 
    } else { 
        "plan-$envNameSafe" 
    }
    
    $pipeline += @"

      - label: ":rocket: $envName - Apply"
        key: "apply-$envNameSafe"
        depends_on: "$dependsOn"
        command: "powershell -File .\\scripts\\Apply-TerraformEnvironment.ps1 -EnvironmentName `"$envName`""
        artifact_paths:
          - "$envName/outputs-$envName.json"
          - "$envName/apply-summary-$envName.txt"
          - "$envName/backups/*.tfstate"
        agents:
          queue: "windows"
        env:
          ENVIRONMENT_NAME: "$envName"
        if: build.branch == "main"
"@
}

# Add final steps
$pipeline += @"

  - wait

  - label: ":bell: Deployment Notification"
    key: "notify-complete"
    command: "powershell -File .\\scripts\\Send-DeploymentNotification.ps1"
    agents:
      queue: "windows"
    if: build.branch == "main"

  - label: ":broom: Cleanup"
    key: "cleanup"
    command: "powershell -File .\\scripts\\Cleanup-TerraformArtifacts.ps1"
    agents:
      queue: "windows"
    allow_dependency_failure: true
"@

# Write pipeline to file
$pipeline | Out-File -FilePath "dynamic-pipeline.yml" -Encoding utf8

Write-Host ""
Write-Host "--- Pipeline preview:"
Write-Host "────────────────────────────────────────────────────────────────"
Get-Content "dynamic-pipeline.yml" | Write-Host
Write-Host "────────────────────────────────────────────────────────────────"
Write-Host ""

# Upload to Buildkite
Write-Host "--- Uploading pipeline to Buildkite"
buildkite-agent pipeline upload dynamic-pipeline.yml

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════"
Write-Host "✅ Dynamic pipeline generated and uploaded"
Write-Host "Environments: $envList"
Write-Host "═══════════════════════════════════════════════════════════════"
