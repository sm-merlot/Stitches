# run.ps1 — run Stitches on Windows (debug)
# Usage: ./run.ps1
#
# For the full task runner (build, test, etc.) use Git Bash: ./run <command>

$ErrorActionPreference = "Stop"

$gitHash = git rev-parse --short HEAD 2>$null
$secretsArg = if (Test-Path "secrets.json") { "--dart-define-from-file=secrets.json" } else { $null }

$flutterArgs = @("run", "-d", "windows", "--dart-define=GIT_HASH=$gitHash")
if ($secretsArg) { $flutterArgs += $secretsArg }

flutter @flutterArgs
