$ErrorActionPreference = "Stop"

if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
  Write-Warning "trivy not installed – skipping"
  exit 0
}

Write-Host "Running Trivy config scan..."
trivy config . --format json --output trivy-report.json
