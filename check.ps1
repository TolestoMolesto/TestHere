#!/usr/bin/env pwsh
# check.ps1 — one-command verification for PonchoGameRework.
#
# Regenerates the Argon sourcemap, ensures the Roblox type definitions are
# present, then runs StyLua (format), selene (lint) and luau-lsp (type check)
# over src/. Vendored code (Roblox PlayerModule, ProfileStore) is excluded.
#
#   ./check.ps1        # report formatting / lint / type issues
#   ./check.ps1 -Fix   # auto-format with StyLua first, then lint + type check
#
# CLI tools are managed by Rokit (see rokit.toml); run `rokit install` once after cloning.

param([switch]$Fix)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"
$argon    = Join-Path $env:USERPROFILE ".argon\bin\argon.exe"
$stylua   = Join-Path $rokitBin "stylua.exe"
$selene   = Join-Path $rokitBin "selene.exe"
$luaulsp  = Join-Path $rokitBin "luau-lsp.exe"

$ignore = @(
    "**/PlayerModule/**",
    "**/RbxCharacterSounds/**",
    "**/ProfileStore.luau",
    "**/Packages/**",
    "**/ServerPackages/**",
    "**/DevPackages/**"
)

# 1. Refresh the DataModel sourcemap that luau-lsp relies on.
Write-Host "==> sourcemap" -ForegroundColor Cyan
& $argon sourcemap default.project.json -o sourcemap.json -y | Out-Null

# 2. Ensure Roblox API type definitions are present.
if (-not (Test-Path "globalTypes.d.luau")) {
    Write-Host "==> downloading Roblox type definitions" -ForegroundColor Cyan
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" `
        -OutFile "globalTypes.d.luau"
}

$ok = $true

# 3. Formatting.
if ($Fix) {
    Write-Host "`n==> StyLua (format)" -ForegroundColor Cyan
    & $stylua src
} else {
    Write-Host "`n==> StyLua (check)" -ForegroundColor Cyan
    & $stylua --check src
    if ($LASTEXITCODE -ne 0) { $ok = $false }
}

# 4. Lint.
Write-Host "`n==> selene (lint)" -ForegroundColor Cyan
& $selene src
if ($LASTEXITCODE -ne 0) { $ok = $false }

# 5. Type check.
Write-Host "`n==> luau-lsp (type check)" -ForegroundColor Cyan
$ignoreArgs = $ignore | ForEach-Object { "--ignore"; $_ }
& $luaulsp analyze --sourcemap sourcemap.json --defs globalTypes.d.luau --base-luaurc .luaurc @ignoreArgs src
if ($LASTEXITCODE -ne 0) { $ok = $false }

if ($ok) {
    Write-Host "`nAll checks passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nChecks reported issues (see above)." -ForegroundColor Yellow
    exit 1
}
