$ErrorActionPreference = "Stop"

if (-not (Get-Command checkov -ErrorAction SilentlyContinue)) {
  Write-Warning "checkov not installed – skipping"
  exit 0
}

Write-Host "Running Checkov..."
checkov -d .
