$ErrorActionPreference = "Stop"

$current = git describe --tags --abbrev=0 2>$null
if (-not $current) { $current = "0.0.0" }

$parts = $current.TrimStart("v").Split(".")
$next = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"

$next | Out-File next-version.txt
"patch" | Out-File version-type.txt
