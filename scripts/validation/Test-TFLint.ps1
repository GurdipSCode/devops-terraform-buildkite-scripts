$ErrorActionPreference = "Stop"

if (-not (Get-Command tflint -ErrorAction SilentlyContinue)) {
  Write-Warning "tflint not installed – skipping"
  exit 0
}

Write-Host "Running tflint..."
tflint --recursive
