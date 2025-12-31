# scripts/Test-BuildkitePipelines.ps1
$ErrorActionPreference = 'Stop'

Write-Host "=== Checking prerequisites ===" -ForegroundColor Cyan

# Download Buildkite schema
$schemaFile = "buildkite.schema.json"
if (-not (Test-Path $schemaFile)) {
    Write-Host "Downloading Buildkite schema..."
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/buildkite/pipeline-schema/main/schema.json" `
        -OutFile $schemaFile
}

Write-Host "=== Linting Buildkite pipelines ===" -ForegroundColor Cyan

$failed = $false
$pipelines = Get-ChildItem -Path "pipelines" -Recurse -Include "*.yml", "*.yaml" -ErrorAction SilentlyContinue

if (-not $pipelines) {
    Write-Host "[WARN] No pipeline files found in pipelines/" -ForegroundColor Yellow
    exit 0
}

foreach ($file in $pipelines) {
    Write-Host ""
    Write-Host "[CHECK] $($file.Name)" -ForegroundColor White
    
    # Schema validation
    Write-Host "  -> Schema validation" -ForegroundColor Gray
    $schemaResult = check-jsonschema --schemafile $schemaFile $file.FullName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [PASS] Schema valid" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Schema invalid" -ForegroundColor Red
        Write-Host $schemaResult
        $failed = $true
    }
    
    # OPA policy validation
    if (Test-Path "opa") {
        Write-Host "  -> Policy validation" -ForegroundColor Gray
        $policyResult = conftest test $file.FullName --policy opa 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [PASS] Policies passed" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Policy violations" -ForegroundColor Red
            Write-Host $policyResult
            $failed = $true
        }
    } else {
        Write-Host "  [SKIP] No opa/ policy folder found" -ForegroundColor Yellow
    }
}

Write-Host ""
if ($failed) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "[FAILED] Pipeline validation failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
} else {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "[PASSED] All pipelines valid" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    exit 0
}
