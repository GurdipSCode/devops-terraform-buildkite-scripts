$ErrorActionPreference = "Stop"

$examples = $env:EXAMPLE_DIRS -split ","

foreach ($dir in $examples) {
  Write-Host "Planning example: $dir"
  Push-Location $dir
  terraform init -backend=false -input=false
  terraform plan -input=false
  Pop-Location
}
