$ErrorActionPreference = "Stop"

$version = Get-Content next-version.txt

git tag "v$version"
git push origin "v$version"

Write-Host "Released v$version"
