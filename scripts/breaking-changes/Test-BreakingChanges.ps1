$ErrorActionPreference = "Stop"
$breaking = git log origin/main..HEAD --pretty=format:%s | Select-String "BREAKING"
if ($breaking) { "major" | Out-File version-bump-type.txt } else { "minor" | Out-File version-bump-type.txt }
