param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$php = Join-Path $repoRoot '.tools/php/php.exe'
if (!(Test-Path -LiteralPath $php)) { & (Join-Path $PSScriptRoot 'Setup-AdminRuntime.ps1') }
$composer = Join-Path $repoRoot '.tools/composer.phar'
if (!(Test-Path -LiteralPath $composer)) {
    $installer = Join-Path $repoRoot '.tools/composer-setup.php'
    Invoke-WebRequest 'https://getcomposer.org/installer' -OutFile $installer
    $response = (Invoke-WebRequest 'https://composer.github.io/installer.sig').Content
    $expected = if ($response -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response).Trim() } else { $response.Trim() }
    if ((Get-FileHash -LiteralPath $installer -Algorithm SHA384).Hash.ToLower() -ne $expected) { throw 'Composer installer checksum mismatch.' }
    & $php -d "extension_dir=$repoRoot/.tools/php/ext" $installer "--install-dir=$repoRoot/.tools" --filename=composer.phar
    if ($LASTEXITCODE -ne 0) { throw 'Composer installation failed.' }
}
& $php -d "extension_dir=$repoRoot/.tools/php/ext" $composer install "--working-dir=$repoRoot/admin" --no-dev --prefer-dist --no-interaction
if ($LASTEXITCODE -ne 0) { throw 'Admin dependency installation failed.' }
