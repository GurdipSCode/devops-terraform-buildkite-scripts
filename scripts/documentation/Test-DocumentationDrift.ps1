$ErrorActionPreference = "Stop"
if (git status --porcelain README.md) { exit 1 }
