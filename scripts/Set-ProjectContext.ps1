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
