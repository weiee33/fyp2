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

Administrator: **angethan765@gmail.com**. Sign in with your existing password and the code from your enrolled authenticator. **weiee0303@gmail.com is a customer account.** No password is set or supplied by this repository. See [admin setup](docs/admin-setup.md) for recovery.

## Customer modules and FPX testing

Customer modules 5–10 now use guarded database APIs for discovery, profile/address management, provider-approved bookings, payment receipts, reviews and persisted notifications. The flow is **request a slot → provider accepts → customer pays → provider performs service → customer reviews**.

Read [customer integration and verification](docs/customer-modules.md) and [Stripe FPX test setup](docs/fpx-test-setup.md). Test checkout requires your own Stripe test account and server-side secrets. Payment cannot be marked successful by the app. Background push/email delivery and AI remain outside this completed integration pass.

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

Customer account, recovery, settings and provider chat setup/acceptance checks are in [Customer account and chat](docs/customer-account-chat.md). The Supabase recovery email template is versioned in `supabase/templates/recovery.html`.

```powershell
.\.tools\php\php.exe -d "extension_dir=$PWD/.tools/php/ext" admin/tests/run.php
```

HTTP tests use a local stub and isolated temporary application, never live records. Database tests run inside `BEGIN`/`ROLLBACK`; see [test plan](docs/database-audit/test-plan.md). GitHub Actions runs PHP lint and HTTP tests.

`admin/public` is the sole web document root. Server code is in `admin/src` and `admin/views`. Database upgrades/tests are in `supabase`; the existing Flutter starter is in its original folders.

Migrations upgrade the existing FYP schema; they are not an empty-project bootstrap. Do not reapply recorded migrations. Never commit `admin/.env`, sessions, passwords or Supabase secret/service-role keys.
