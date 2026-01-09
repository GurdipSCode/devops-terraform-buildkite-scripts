$ErrorActionPreference = "Stop"

Write-Host "Running terraform fmt check..."

terraform fmt -recursive -check

Write-Host "Terraform formatting OK"
