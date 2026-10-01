param(
    [ValidateRange(1024, 65535)][int]$AppPort = 8090,
    [ValidateRange(1024, 65535)][int]$StubPort = 8091
)
$ErrorActionPreference = 'Stop'
if ($AppPort -eq $StubPort) { throw 'AppPort and StubPort must be different.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$adminRoot = Join-Path $repoRoot 'admin'
$php = Join-Path $repoRoot '.tools\php\php.exe'
if (!(Test-Path -LiteralPath $php)) { throw 'The portable PHP runtime is missing from .tools/php.' }
foreach ($port in @($AppPort, $StubPort)) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
    try { $listener.Start() } finally { $listener.Stop() }
}

$previewRoot = Join-Path ([IO.Path]::GetTempPath()) ('locallife-admin-preview-' + [Guid]::NewGuid().ToString('N'))
$siteRoot = Join-Path $previewRoot 'site'
$null = New-Item -ItemType Directory -Path $siteRoot -Force
foreach ($directory in @('src', 'public', 'views')) {
    Copy-Item -LiteralPath (Join-Path $adminRoot $directory) -Destination (Join-Path $siteRoot $directory) -Recurse
}

# Only this copied site gets the fixture label. No production source, .env or Auth bypass is changed.
$layoutPath = Join-Path $siteRoot 'views\layout.php'
$layout = Get-Content -LiteralPath $layoutPath -Raw
$layout = $layout.Replace(' · Local Life</title>', ' · FIXTURE PREVIEW · Local Life</title>')
$layout = $layout.Replace('<a class="skip-link"', '<div class="fixture-preview" role="status">TEST DATA PREVIEW · Local Supabase fixture · No real accounts or records</div><a class="skip-link"')
Set-Content -LiteralPath $layoutPath -Value $layout -Encoding utf8
$cssPath = Join-Path $siteRoot 'public\assets\admin.css'
Add-Content -LiteralPath $cssPath -Encoding utf8 -Value '.fixture-preview{position:fixed;z-index:1000;inset:auto 0 0;background:#282522;color:#fff;text-align:center;font:600 11px/24px system-ui,sans-serif;letter-spacing:.025em;pointer-events:none}'
$reportPath = Join-Path $siteRoot 'views\booking-report.php'
if (Test-Path -LiteralPath $reportPath) {
    $report = Get-Content -LiteralPath $reportPath -Raw
    $report = $report.Replace('Local Life · Booking report</title>', 'FIXTURE PREVIEW · Local Life · Booking report</title>')
    $report = $report.Replace('<div class="report-controls">', '<div class="report-controls"><p>TEST DATA PREVIEW · Synthetic booking records only</p>')
    Set-Content -LiteralPath $reportPath -Value $report -Encoding utf8
}

$fixtureEnvironment = @{
    APP_ENV = 'test'
    APP_URL = "http://127.0.0.1:$AppPort"
    SUPABASE_URL = "http://127.0.0.1:$StubPort"
    SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_test_contract'
    TEST_STATE_DIR = $previewRoot
}
($fixtureEnvironment.GetEnumerator() | Where-Object Key -ne 'TEST_STATE_DIR' | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -LiteralPath (Join-Path $siteRoot '.env') -Encoding utf8
Set-Content -LiteralPath (Join-Path $previewRoot 'fixture-state.json') -Value '{"visual_preview":true}' -Encoding ascii
$originalEnvironment = @{}
$processes = @()
try {
    foreach ($key in $fixtureEnvironment.Keys) {
        $originalEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $fixtureEnvironment[$key], 'Process')
    }
    $extensionDir = Join-Path $repoRoot '.tools\php\ext'
    $phpArguments = @('-n', '-d', "extension_dir=`"$extensionDir`"", '-d', 'extension=curl', '-d', 'extension=mbstring', '-d', 'extension=fileinfo', '-d', 'display_errors=0', '-d', 'log_errors=1', '-d', 'date.timezone=Asia/Kuala_Lumpur')
    $stubRouter = Join-Path $PSScriptRoot 'supabase_stub.php'
    $stub = Start-Process -FilePath $php -ArgumentList ($phpArguments + @('-S', "127.0.0.1:$StubPort", "`"$stubRouter`"")) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $previewRoot 'stub.stdout.log') -RedirectStandardError (Join-Path $previewRoot 'stub.stderr.log') -PassThru
    $processes += $stub
    $appRouter = Join-Path $siteRoot 'public\router.php'
    $app = Start-Process -FilePath $php -ArgumentList ($phpArguments + @('-S', "127.0.0.1:$AppPort", "`"$appRouter`"")) -WorkingDirectory (Join-Path $siteRoot 'public') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $previewRoot 'app.stdout.log') -RedirectStandardError (Join-Path $previewRoot 'app.stderr.log') -PassThru
    $processes += $app
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$AppPort/?page=login" -TimeoutSec 2
            if ($response.StatusCode -eq 200 -and $response.Content.Contains('TEST DATA PREVIEW')) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 100
    }
    if (!$ready) { throw "The preview did not start correctly. Check logs in $previewRoot." }
    $metadata = [ordered]@{
        app_url = "http://127.0.0.1:$AppPort/?page=login"
        stub_url = "http://127.0.0.1:$StubPort"
        app_pid = $app.Id
        stub_pid = $stub.Id
        temporary_folder = $previewRoot
        email = 'admin@example.test'
        password = 'test-password-only'
        authenticator_code = '123456'
        data = 'Synthetic fixture records only; no real Supabase access'
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $previewRoot 'preview.json') -Encoding utf8
    $metadata | ConvertTo-Json
} catch {
    foreach ($process in $processes) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
    throw
} finally {
    foreach ($key in $fixtureEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $originalEnvironment[$key], 'Process') }
}
