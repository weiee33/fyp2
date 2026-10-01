# Local Life Service Assistant

FYP 2 implementation for Ang Wei Ee and Lam Yi Ming. The dedicated **PHP admin website** is implemented first, with an orange-and-white theme and Supabase Auth, PostgreSQL and Storage. The latest teammate provider code on `master` is preserved. Its compatibility changes for the hardened database are recorded in [provider integration review](docs/provider-integration-review.md), for the subsequent mobile phase.

## Run the admin website on Windows

Open this repository in Android Studio, then use its PowerShell terminal:

```powershell
.\scripts\Setup-AdminRuntime.ps1
# Only if admin/.env does not already exist:
Copy-Item admin/.env.example admin/.env
# Edit admin/.env to set your Supabase publishable or legacy anon key.
.\scripts\Start-Admin.ps1
```

Open **http://127.0.0.1:8088** in your browser. PHP runs independently of the Flutter emulator; Android Studio is the editor. The script installs a checksum-verified repository-local PHP runtime.

First administrator: **weiee0303@gmail.com**. Its verified Auth account is already present in the connected project. Sign in using your existing password; the reserved database invitation links its admin profile on successful login. Complete authenticator verification before accessing records. For password recovery, configure the callback as described in [setup](docs/admin-setup.md). No password is supplied by this repository.

## Admin modules

- Administrator sign-in, invited activation, password recovery and TOTP MFA.
- User management, provider/credential verification and review moderation.
- Category/subcategory management and icon uploads.
- Booking monitoring, controlled transitions, attributed history and disputes.
- Super Admin refund requests and audit trail.
- Analytics with date/category/region/provider filters, revenue/popularity charts, provider performance, CSV and booking reports saved as PDF through the browser.

Refund requests do not move funds. Notifications are recorded and email delivery is queued; gateway processing and an email worker remain external integration work.

See [Chapter 4 coverage and added features](docs/admin-modules.md), [database audit](docs/database-audit/README.md), and [setup/deployment](docs/admin-setup.md).

## Verification

```powershell
.\.tools\php\php.exe -d "extension_dir=$PWD/.tools/php/ext" admin/tests/run.php
```

HTTP tests use a local stub and isolated temporary application, never live records. Database tests run inside `BEGIN`/`ROLLBACK`; see [test plan](docs/database-audit/test-plan.md). GitHub Actions runs PHP lint and HTTP tests.

`admin/public` is the sole web document root. Server code is in `admin/src` and `admin/views`. Database upgrades/tests are in `supabase`; the existing Flutter starter is in its original folders.

Migrations upgrade the existing FYP schema; they are not an empty-project bootstrap. Do not reapply recorded migrations. Never commit `admin/.env`, sessions, passwords or Supabase secret/service-role keys.
