ErrorActionPreference = "Stop"

if (-not (Get-Command git-cliff -ErrorAction SilentlyContinue)) {
  Write-Warning "git-cliff not installed – skipping"
  exit 0
}

git-cliff --unreleased > CHANGELOG-PREVIEW.md
