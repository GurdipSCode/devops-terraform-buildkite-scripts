$ErrorActionPreference = "Stop"

$examples = $env:EXAMPLE_DIRS -split ","

foreach ($dir in $examples) {
  Write-Host "Validating example: $dir"
  Push-Location $dir
  terraform init -backend=false -input=false
  terraform validate
  Pop-Location
}
