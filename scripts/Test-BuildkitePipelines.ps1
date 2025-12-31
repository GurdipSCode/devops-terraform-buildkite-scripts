# .buildkite/scripts/Test-BuildkitePipelines.ps1
$ErrorActionPreference = 'Stop'

Write-Host "=== Checking prerequisites ===" -ForegroundColor Cyan


Write-Host "=== Downloading Buildkite schema ===" -ForegroundColor Cyan
Invoke-WebRequest `
    -Uri "https://raw.githubusercontent.com/buildkite/pipeline-schema/main/schema.json" `
    -OutFile "buildkite.schema.json"

Write-Host "=== Linting Buildkite pipelines ===" -ForegroundColor Cyan

$failed = $false
$pipelines = Get-ChildItem -Path "pipelines" -Recurse -Include "*.yml", "*.yaml"

foreach ($file in $pipelines) {
    Write-Host "[CHECK] Validating $($file.FullName)" -ForegroundColor White
    
    $jsonFile = "$($file.FullName).json"
    
    # Convert YAML to JSON
    yaml2json $file.FullName | Out-File -Encoding utf8 $jsonFile
    
    # Schema validation
    Write-Host "  -> Schema validation" -ForegroundColor Gray
    ajv validate -s buildkite.schema.json -d $jsonFile --strict=false
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Schema validation failed" -ForegroundColor Red
        $failed = $true
    }
    
    # OPA policy validation
    Write-Host "  -> OPA policy validation" -ForegroundColor Gray
    opa eval --fail-defined --format pretty --data opa --input $jsonFile "data.buildkite.deny"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] OPA validation failed" -ForegroundColor Red
        $failed = $true
    }
    
    # Cleanup
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($failed) {
    Write-Host ""
    Write-Host "[FAILED] Pipeline validation failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[PASSED] All pipelines valid" -ForegroundColor Green
