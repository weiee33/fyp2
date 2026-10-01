param([switch]$Force)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot '.tools/php'
$runtimeExe = Join-Path $runtimePath 'php.exe'
if (!(Test-Path -LiteralPath $runtimeExe) -or $Force) {
    New-Item -ItemType Directory -Force -Path $runtimePath | Out-Null
    $archivePath = Join-Path $repoRoot '.tools/php.zip'
    Invoke-WebRequest -Uri 'https://windows.php.net/downloads/releases/php-8.4.26-nts-Win32-vs17-x64.zip' -OutFile $archivePath
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
    if ($actualHash -ne 'da68394f9193b7f6b89d0c76861a4034ae10efee7fd55a7255d8118c2acf70d7') { throw 'PHP download checksum did not match the official release.' }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimePath -Force
}
@'
extension_dir="ext"
extension=curl
extension=openssl
extension=mbstring
extension=fileinfo
date.timezone="Asia/Kuala_Lumpur"
display_errors=Off
log_errors=On
'@ | Set-Content -LiteralPath (Join-Path $runtimePath 'php.ini') -Encoding utf8
& $runtimeExe -v
Write-Host 'PHP runtime is ready. It is local to this repository.'
