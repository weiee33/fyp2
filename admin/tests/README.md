# PHP administrator HTTP regression tests

Run from the repository root on Windows:

```powershell
& .\.tools\php\php.exe -d extension_dir=.tools/php/ext admin/tests/run.php
```

Or use an installed PHP 8.2+ runtime with `curl` and `mbstring` enabled:

```text
php admin/tests/run.php
```

The suite copies the website into a randomly named temporary directory, starts two loopback PHP servers, and sends browser-style HTTP requests with a cookie jar. One server runs the actual website; the other implements local Supabase Auth, RPC, and Storage contracts. It never connects to the real Supabase project, changes real records, sends real email, or requires passwords or API keys.

It exercises account activation, authenticator enrollment and verification, stale-session cleanup, CSRF, rendering populated modules/details, HTML escaping, safe icon uploads, optimistic concurrency errors, analytics filters and exports, paginated CSV and print reports, token refresh, idle expiry, PKCE recovery, logout, and unsafe configuration rejection. Fixture responses mirror the migration's JSON contracts. Database permissions, RLS, SQL constraints, real MFA delivery and real gateway operations still require separate database/integration checks.

Temporary directories are removed on success. On failure their logs remain in the reported temporary location for diagnosis; each failed case includes a reason, and the command exits with status 1.

For a persistent Windows browser preview with synthetic data:

```powershell
& .\admin\tests\start-preview.ps1
```

The script starts two hidden loopback servers, uses a temporary copy of the website, and prints the URL, fake credentials, process IDs, and temporary folder. A visible **TEST DATA PREVIEW** banner distinguishes it from the real project. The original `admin/.env` is never copied or edited. Stop only the two printed process IDs when finished; logs and the copied site remain in the reported temporary folder for inspection.
