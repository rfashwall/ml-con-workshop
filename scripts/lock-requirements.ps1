# Generate a cross-platform lock file from the flexible root requirements.txt.
#
# Usage:
#   .\scripts\lock-requirements.ps1
#
# Produces: requirements.lock
#
# Re-run only when root requirements change. Participants do NOT need this —
# they install from requirements.txt. The lock file is for CI reproducibility.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

python -m pip show pip-tools 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> Installing pip-tools"
    python -m pip install --quiet pip-tools
}

Write-Host "==> Compiling requirements.txt -> requirements.lock"
python -m piptools compile `
    --strip-extras `
    --no-emit-index-url `
    --output-file requirements.lock `
    requirements.txt

$lines = (Get-Content requirements.lock).Count
Write-Host "==> Done: $lines lines pinned."
Write-Host "   Commit requirements.lock alongside requirements.txt."
