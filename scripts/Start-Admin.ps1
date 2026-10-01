param([ValidateRange(1024,65535)][int]$Port = 8088)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeExe = Join-Path $repoRoot '.tools/php/php.exe'
if (!(Test-Path -LiteralPath $runtimeExe)) { & (Join-Path $PSScriptRoot 'Setup-AdminRuntime.ps1') }
if (!(Test-Path -LiteralPath (Join-Path $repoRoot 'admin/.env'))) { throw 'Copy admin/.env.example to admin/.env and configure the publishable key first.' }
Write-Host "Admin website: http://127.0.0.1:$Port"
Push-Location $repoRoot
try {
    & $runtimeExe -d "extension_dir=$repoRoot/.tools/php/ext" -S "127.0.0.1:$Port" -t admin/public admin/public/router.php
} finally { Pop-Location }
