param([switch]$Force)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tools/php'))
$runtimeExe = Join-Path $runtimePath 'php.exe'
if (!(Test-Path -LiteralPath $runtimeExe) -or $Force) {
    $running = Get-Process -Name php -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $runtimeExe }
    if ($running) { throw 'Stop PHP servers using this repository runtime before replacing it, then run setup again.' }
    New-Item -ItemType Directory -Force -Path $runtimePath | Out-Null
    $archivePath = Join-Path $repoRoot '.tools/php.zip'
    $archiveName = 'php-8.4.27-nts-Win32-vs17-x64.zip'
    try {
        Invoke-WebRequest -Uri "https://downloads.php.net/~windows/releases/$archiveName" -OutFile $archivePath
    } catch {
        if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
        Invoke-WebRequest -Uri "https://downloads.php.net/~windows/releases/archives/$archiveName" -OutFile $archivePath
    }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
    if ($actualHash -ne '93bd8a815a52156606fb906d0573437908c61f96e2cc52c03a51e36a41bf5236') { throw 'PHP download checksum did not match the official release.' }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimePath -Force -ErrorAction Stop
    $installedVersion = & $runtimeExe -n -r 'echo PHP_VERSION;'
    if ($LASTEXITCODE -ne 0 -or $installedVersion -ne '8.4.27') { throw 'PHP installation verification failed. Run setup again with -Force.' }
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
if ($LASTEXITCODE -ne 0) { throw 'PHP could not start. Check the runtime and Windows Visual C++ dependencies.' }
& $runtimeExe -d "extension_dir=$runtimePath/ext" -r 'foreach (["curl", "openssl", "mbstring", "fileinfo"] as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "Missing PHP extension: ".$extension.PHP_EOL); exit(1); } }'
if ($LASTEXITCODE -ne 0) { throw 'Required PHP extensions could not load. Check the runtime installation.' }
Write-Host 'PHP runtime is ready. It is local to this repository.'
