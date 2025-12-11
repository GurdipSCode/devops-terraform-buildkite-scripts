#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates dynamic Buildkite pipeline steps for each environment
.DESCRIPTION
    Creates plan/apply steps for each environment defined in ENVIRONMENTS variable
#>

$ErrorActionPreference = "Stop"

# Determine scripts path (central repo or local for testing)
$scriptsPath = if ($env:BUILDKITE) {
    # In Buildkite, scripts are cloned to buildkite-scripts/scripts
    "buildkite-scripts/scripts"
} else {
    # For local testing, assume scripts are in current directory or override with SCRIPTS_PATH
    if ($env:SCRIPTS_PATH) { $env:SCRIPTS_PATH } else { "." }
}

Write-Host "Using scripts from: $scriptsPath"

Write-Host "--- 🔄 Generating dynamic environment steps"

# Get environments from environment variable
$environments = $env:ENVIRONMENTS -split '\s+' | Where-Object { $_ }

if (-not $environments) {
    Write-Host "❌ Error: No environments defined in ENVIRONMENTS variable" -ForegroundColor Red
    exit 1
}

Write-Host "Environments to deploy: $($environments -join ', ')"

# Start building the pipeline YAML
$pipeline = @{
    steps = @()
}

# Track previous step for dependencies
$previousApplyStep = $null

foreach ($env in $environments) {
    $envUpper = $env.ToUpper()
    
    # Load Secrets Step
    $secretsStep = @{
        label = ":key: $envUpper - Load Secrets"
        key = "secrets-$env"
        env = @{
            LYNX_ENVIRONMENT = $env
        }
        commands = @(
            "pwsh -File $scriptsPath/fetch-vault-secrets.ps1 -Environment $env",
            "buildkite-agent artifact upload `$env:TEMP\vault-secrets-$env.ps1"
        )
        agents = @{
            queue = "terraform"
        }
    }
    
    # Add dependency on previous environment's apply step (for sequential deployment)
    if ($previousApplyStep) {
        $secretsStep.depends_on = $previousApplyStep
    }
    else {
        $secretsStep.depends_on = "security-scan"
    }
    
    $pipeline.steps += $secretsStep
    
    # Plan Step
    $planStep = @{
        label = ":terraform: $envUpper - Plan"
        key = "plan-$env"
        depends_on = "secrets-$env"
        env = @{
            LYNX_ENVIRONMENT = $env
        }
        commands = @(
            "# Download secrets",
            "buildkite-agent artifact download vault-secrets-$env.ps1 `$env:TEMP\",
            ". `$env:TEMP\vault-secrets-$env.ps1",
            "",
            "# Configure Lynx backend",
            "pwsh -File /configure-lynx-backend.ps1 -Environment $env",
            "",
            "# Initialize Terraform",
            "terraform init -input=false",
            "",
            "# Run Terraform plan",
            "terraform plan -out=tfplan-$env -input=false",
            "",
            "# Save plan as text for Fabric analysis",
            "terraform show -no-color tfplan-$env > tfplan-$env.txt",
            "",
            "# Upload artifacts",
            "buildkite-agent artifact upload tfplan-$env",
            "buildkite-agent artifact upload tfplan-$env.txt"
        )
        agents = @{
            queue = "terraform"
        }
    }
    
    $pipeline.steps += $planStep
    
    # Fabric Summary Step
    $fabricStep = @{
        label = ":robot: $envUpper - AI Summary"
        key = "fabric-$env"
        depends_on = "plan-$env"
        env = @{
            LYNX_ENVIRONMENT = $env
        }
        commands = @(
            "# Download plan text",
            "buildkite-agent artifact download tfplan-$env.txt .",
            "",
            "# Generate AI summary",
            "pwsh -File /run-fabric-summary.ps1 -PlanFile tfplan-$env.txt -Environment $env"
        )
        agents = @{
            queue = "terraform"
        }
    }
    
    $pipeline.steps += $fabricStep
    
    # Overmind Blast Radius Step
    $overmindStep = @{
        label = ":mag: $envUpper - Blast Radius"
        key = "overmind-$env"
        depends_on = "plan-$env"
        env = @{
            LYNX_ENVIRONMENT = $env
        }
        commands = @(
            "# Download plan binary",
            "buildkite-agent artifact download tfplan-$env .",
            "",
            "# Run Overmind analysis",
            "pwsh -File /run-overmind-analysis.ps1 -PlanFile tfplan-$env -Environment $env"
        )
        agents = @{
            queue = "terraform"
        }
    }
    
    $pipeline.steps += $overmindStep
    
    # Approval Block
    $approvalPrompt = if ($env -eq "prd") {
        @"
⚠️  PRODUCTION DEPLOYMENT

You are about to deploy to PRODUCTION.
Please review:
- Terraform plan
- AI summary (Fabric)
- Blast radius analysis (Overmind)
- Security scans

Environment: $envUpper
Team: `$env:LYNX_TEAM
Project: `$env:LYNX_PROJECT

Continue?
"@
    }
    else {
        "Review and approve deployment to $envUpper environment`n`nCheck the AI summary and blast radius analysis before proceeding."
    }
    
    $blockStep = @{
        block = ":rocket: Deploy to $envUpper ?"
        key = "approve-$env"
        depends_on = @("fabric-$env", "overmind-$env")
        prompt = $approvalPrompt
    }
    
    # Add fields for production
    if ($env -eq "prd") {
        $blockStep.fields = @(
            @{
                text = "Deployment Reason"
                key = "deployment-reason"
                required = $true
            },
            @{
                select = "Change Risk Level"
                key = "risk-level"
                required = $true
                options = @(
                    @{
                        label = "Low (config change, no impact)"
                        value = "low"
                    },
                    @{
                        label = "Medium (minor feature, limited impact)"
                        value = "medium"
                    },
                    @{
                        label = "High (major change, significant impact)"
                        value = "high"
                    }
                )
            }
        )
    }
    
    $pipeline.steps += $blockStep
    
    # Apply Step
    $applyStep = @{
        label = ":terraform: $envUpper - Apply"
        key = "apply-$env"
        depends_on = "approve-$env"
        env = @{
            LYNX_ENVIRONMENT = $env
        }
        commands = @(
            "# Download secrets",
            "buildkite-agent artifact download vault-secrets-$env.ps1 `$env:TEMP\",
            ". `$env:TEMP\vault-secrets-$env.ps1",
            "",
            "# Configure Lynx backend",
            "pwsh -File /configure-lynx-backend.ps1 -Environment $env",
            "",
            "# Initialize Terraform",
            "terraform init -input=false",
            "",
            "# Download plan",
            "buildkite-agent artifact download tfplan-$env .",
            "",
            "# Apply Terraform",
            "terraform apply -input=false tfplan-$env",
            "",
            "# Cleanup secrets",
            "Remove-Item `$env:TEMP\vault-secrets-$env.ps1 -ErrorAction SilentlyContinue",
            "",
            "Write-Host '✓ Deployment to $envUpper complete' -ForegroundColor Green"
        )
        agents = @{
            queue = "terraform"
        }
        concurrency = 1
        concurrency_group = "terraform-$env"
    }
    
    $pipeline.steps += $applyStep
    
    # Track this apply step for next environment's dependency
    $previousApplyStep = "apply-$env"
}

# Add final notification step
$notificationStep = @{
    label = ":white_check_mark: Deployment Complete"
    depends_on = $previousApplyStep
    commands = @(
        "Write-Host '========================================'",
        "Write-Host '✓ All environments deployed successfully' -ForegroundColor Green",
        "Write-Host '========================================'",
        "Write-Host ''",
        "Write-Host 'Deployed environments: $($environments -join ', ')'"
    )
    agents = @{
        queue = "terraform"
    }
}

$pipeline.steps += $notificationStep

# Convert to YAML and upload
$yamlContent = $pipeline | ConvertTo-Yaml

Write-Host ""
Write-Host "Generated pipeline:"
Write-Host $yamlContent

# Upload pipeline
Write-Host ""
Write-Host "--- 📤 Uploading dynamic pipeline"
$yamlContent | buildkite-agent pipeline upload

Write-Host "✓ Dynamic pipeline uploaded" -ForegroundColor Green

# Helper function to convert PowerShell object to YAML
function ConvertTo-Yaml {
    param($obj, $indent = 0)
    
    $yaml = ""
    $indentStr = "  " * $indent
    
    if ($obj -is [System.Collections.IDictionary]) {
        foreach ($key in $obj.Keys) {
            $value = $obj[$key]
            if ($value -is [System.Collections.IDictionary] -or $value -is [System.Collections.IList]) {
                $yaml += "$indentStr$key`:`n"
                $yaml += ConvertTo-Yaml $value ($indent + 1)
            }
            elseif ($value -is [string] -and $value.Contains("`n")) {
                # Multi-line string
                $yaml += "$indentStr$key`: |`n"
                foreach ($line in $value -split "`n") {
                    $yaml += "$indentStr  $line`n"
                }
            }
            else {
                $yaml += "$indentStr$key`: $value`n"
            }
        }
    }
    elseif ($obj -is [System.Collections.IList]) {
        foreach ($item in $obj) {
            if ($item -is [System.Collections.IDictionary]) {
                $yaml += "$indentStr-`n"
                $yaml += ConvertTo-Yaml $item ($indent + 1)
            }
            elseif ($item -is [System.Collections.IList]) {
                $yaml += "$indentStr-`n"
                $yaml += ConvertTo-Yaml $item ($indent + 1)
            }
            else {
                $yaml += "$indentStr- $item`n"
            }
        }
    }
    
    return $yaml
}
