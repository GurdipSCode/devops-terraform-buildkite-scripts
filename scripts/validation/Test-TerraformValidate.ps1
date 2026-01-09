$ErrorActionPreference = "Stop"

Write-Host "Running terraform validate..."

terraform init -backend=false -input=false
terraform validate

Write-Host "Terraform validation OK"
