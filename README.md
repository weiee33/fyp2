# Local Life Service Assistant

Local Life Service Assistant connects customers with local household service providers. The Flutter app serves customers and providers; a separate PHP website handles administration. Supabase provides authentication, PostgreSQL and storage, with Stripe sandbox checkout, Firebase customer notifications and Gemini-powered assistance.

## Three connected experiences

| Part | Main features |
| --- | --- |
| Customer | Discover services, manage addresses, request appointments, pay after provider acceptance, download receipts, chat, review completed services and contact support. AI Chat and AI Agent assist with supported tasks. |
| Provider | Manage business details, credentials, services and availability; accept requests, track jobs and communicate with customers. |
| Admin | Verify providers, manage users and categories, monitor bookings, moderate reviews, respond to customer support, record refund requests, review analytics and manage admin invitations. |

The normal flow is **customer requests → provider accepts → customer pays → provider completes → customer reviews**. Customers and providers share the mobile login; the stored account role determines their destination. Registration includes the account-type choice. Admin accounts use the dedicated website and require MFA.

## Run the mobile app

Prerequisites: Flutter **3.38.8**, its bundled Dart SDK, Android Studio/Android SDK, and a device or emulator. Run from the repository root:

```powershell
flutter pub get
flutter run
```

The current project uses `lib/Provider/core/supabase_config.dart` for its public Supabase URL/key. Android Firebase configuration is in `android/app/google-services.json`. If using your own backend, replace these public project settings and configure the matching Auth, Storage and Edge Functions. Never put service-role, Stripe secret, Gemini or email API keys in the app.

English, Chinese and Malay interface translations are supported. User-written chat messages, reviews and AI conversations retain their own language.

## Run the admin website

PHP **8.4** with cURL, OpenSSL, mbstring, DOM and fileinfo is required. PDF exports use locked Composer dependencies; no JavaScript build is needed. On Windows:

```powershell
.\scripts\Setup-AdminRuntime.ps1
.\scripts\Setup-AdminDependencies.ps1
# Only when admin/.env does not exist:
Copy-Item admin/.env.example admin/.env
# Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in admin/.env.
.\scripts\Start-Admin.ps1
```

Open **http://127.0.0.1:8088**. Use an existing administrator account and its authenticator code.

To add another administrator, a Super Admin opens **Admin team**, creates an invitation and shares the activation link. The recipient verifies the invited email and sets up an authenticator. Invitations expire after seven days and can be renewed or revoked before acceptance. Invitation emails are not sent automatically. For access from another computer, deploy the website with HTTPS and configure its public `APP_URL`; a localhost link is only local.

Serve only `admin/public` as the web root. Keep `admin/.env` and `admin/var` private. See [admin setup](docs/admin-setup.md) for Auth templates, redirects, MFA, deployment and recovery.

Analytics exports CSV or PDF using the last applied filters. Select chart points, categories or provider rows to inspect exact values. Suspended customers retain view-only access and Help Centre support; other account actions remain blocked by the backend.

## Backend and integrations

- **Database:** `supabase/migrations` contains upgrades to the existing FYP schema, not a complete empty-project bootstrap. Check applied migration history before upgrading; do not replay installed migrations.
- **Payments:** Stripe remains in sandbox mode. Payment success is recorded by verified gateway events, never by the client. Admin refund requests record an intention; they do not themselves move money. See [payment setup](docs/fpx-test-setup.md).
- **Notifications and receipts:** customer push and receipt-email delivery use the delivery worker. The shared email test sender supports only its configured owner mailbox; other recipients require a verified domain. See [delivery setup](docs/customer-alerts-and-receipts.md).
- **Support:** customer questions, complaints and booking requests appear in **Support & disputes**. Admin responses appear on the customer's matching request in its separate Support response card.

Additional guides: [customer workflows](docs/customer-modules.md), [account and chat](docs/customer-account-chat.md), [provider integration](docs/provider-integration-review.md), [admin modules](docs/admin-modules.md), and [database verification](docs/database-audit/test-plan.md). Older review documents describe their dated implementation pass; use the current code and migration history for deployment state.

## Verify changes

```powershell
flutter test --no-pub
flutter test --no-pub --platform chrome test/customer_recovery_web_test.dart
python tool/check_localization.py
.\.tools\php\php.exe -d "extension_dir=$PWD/.tools/php/ext" admin/tests/run.php
```

The PHP tests use isolated local fixtures and send no real email. Database regression scripts use synthetic records inside a transaction that must end in `ROLLBACK`; follow [the test plan](docs/database-audit/test-plan.md). GitHub Actions runs the suites relevant to each changed area.

## Repository map

- `lib/Customer`, `lib/Provider`, `lib/shared` — Flutter screens, services and shared authentication/localization.
- `admin/public`, `admin/src`, `admin/views` — PHP website, server code and templates.
- `supabase/migrations`, `supabase/functions`, `supabase/tests` — database changes, trusted backend endpoints and regression checks.
- `docs`, `scripts`, `test` — operational guides, local setup and Flutter tests.

Keep passwords, sessions, `.env` files and server credentials out of Git.
