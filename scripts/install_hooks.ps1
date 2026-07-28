# Points git at the tracked hooks in scripts/hooks/ so pre-commit runs the
# unit tier and pre-push runs the full suite. Run this once per clone.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location $repoRoot
try {
    git config core.hooksPath scripts/hooks
    Write-Host "Installed git hooks: core.hooksPath = scripts/hooks"
    Write-Host "pre-commit runs the 'unit' tier; pre-push runs 'all'."
    Write-Host "Bypass intentionally with --no-verify when needed."
} finally {
    Pop-Location
}
