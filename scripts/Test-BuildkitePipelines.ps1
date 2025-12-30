# .buildkite/scripts/Test-BuildkitePipelines.ps1
$ErrorActionPreference = 'Stop'

Write-Host "=== Checking prerequisites ===" -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is required on this agent"
    exit 1
}

# AJV + YAML
if (-not (Get-Command ajv -ErrorAction SilentlyContinue)) {
    Write-Host "AJV not found - installing ajv-cli and yaml..."
    npm install -g ajv-cli yaml
} else {
    Write-Host "AJV already installed"
}

# OPA
if (-not (Get-Command opa -ErrorAction SilentlyContinue)) {
    Write-Host "OPA not found - installing via Chocolatey..."
    choco install opa -y
} else {
    Write-Host "OPA already installed"
}

Write-Host "=== Downloading Buildkite schema ===" -ForegroundColor Cyan
Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/buildkite/pipeline-schema/main/schema.json" `
    -OutFile "buildkite.schema.json"

Write-Host "=== Linting Buildkite pipelines ===" -ForegroundColor Cyan

$failed = $false
$pipelines = Get-ChildItem -Path "pipelines" -Recurse -Include "*.yml", "*.yaml"

foreach ($file in $pipelines) {
    Write-Host "🔍 Validating $($file.FullName)" -ForegroundColor White
    
    $jsonFile = "$($file.FullName).json"
    
    # Convert YAML to JSON
    yaml2json $file.FullName | Out-File -Encoding utf8 $jsonFile
    
    # Schema validation
    Write-Host "  → Schema validation" -ForegroundColor Gray
    ajv validate -s buildkite.schema.json -d $jsonFile --strict=false
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ Schema validation failed" -ForegroundColor Red
        $failed = $true
    }
    
    # OPA policy validation
    Write-Host "  → OPA policy validation" -ForegroundColor Gray
    opa eval --fail-defined --format pretty --data opa --input $jsonFile "data.buildkite.deny"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ OPA validation failed" -ForegroundColor Red
        $failed = $true
    }
    
    # Cleanup
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($failed) {
    Write-Host ""
    Write-Host "❌ Pipeline validation failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ All pipelines valid" -ForegroundColor Green
