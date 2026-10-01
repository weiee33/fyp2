# Admin website setup

## Windows development

The mobile environment remains Flutter 3.38.8 / Dart 3.10.7, Android Studio 2025.2.3.9 on Windows 64-bit, and the Pixel 3a emulator. Those tools do not execute PHP. Open `fyp2` in Android Studio and run the separate PHP server from its PowerShell terminal; use a browser for the admin website.

`scripts/Setup-AdminRuntime.ps1` installs PHP 8.4.26 NTS x64 into ignored `.tools/php`, verifies the official archive SHA-256, and enables cURL, OpenSSL, mbstring and fileinfo. No Composer or JavaScript build is required; XAMPP and system PATH remain independent.

```powershell
.\scripts\Setup-AdminRuntime.ps1
# Only if admin/.env does not already exist:
Copy-Item admin/.env.example admin/.env
.\scripts\Start-Admin.ps1
```

Configure ignored `admin/.env`:

```dotenv
APP_ENV=local
APP_URL=http://127.0.0.1:8088
SUPABASE_URL=https://znxhiymvmluxmdaxzxkt.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-or-legacy-anon-key
```

The public key identifies the project; access uses the administrator's Auth token and database permissions. Never use a secret/service-role key. Local configuration is already created on the implementation machine and is ignored by Git.

The server binds localhost and serves only `admin/public`. Stop with Ctrl+C. If changing the port, update `APP_URL`, start with `-Port`, and update the Auth callback URL. Use the same host throughout email confirmation/recovery: the PKCE verifier is kept in that browser's server session.

## First Super Admin

The database reserves **weiee0303@gmail.com**. At final inspection this email had a verified Supabase Auth account with no linked app profile. No password was created, read or changed during implementation.

1. Open `http://127.0.0.1:8088/?page=login` and use the account's existing password. The database accepts the invitation after validating its verified Auth identity.
2. If prompted, set up your authenticator using the QR code and enter its six-digit code. Supabase AAL2 is required again by the database for admin reads and changes.
3. Subsequent logins use the existing authenticator. Keep its secret and codes private.

For an invited email without an Auth account, use **Activate your admin account**, choose your password and confirm the email in the same browser. Ordinary signups cannot become administrators. An existing app profile with matching email and no Auth linkage requires trusted explicit linking; it is never silently taken over.

If the existing password is unavailable, configure the callback below and use **Forgot password?**. Password recovery requires the administrator's authenticator before setting a new password. Lost-authenticator recovery needs a trusted project-owner process; the portal provides no MFA bypass.

## Auth settings

SQL cannot configure Auth URL settings. In [project Auth URL Configuration](https://supabase.com/dashboard/project/znxhiymvmluxmdaxzxkt/auth/url-configuration), add `http://127.0.0.1:8088/?page=callback` to the redirect allowlist. Use `http://127.0.0.1:8088` as Site URL for an admin-only development environment. Preserve the primary Site URL if another app depends on it; this website explicitly requests its admin callback. Keep existing needed allowlist entries.

Configure production URLs separately. Email confirmation/recovery uses Supabase Auth email configuration. Configure SMTP for reliable delivery and check Auth email/rate limits. Real email delivery/redirects are not established by stub tests.

The advisor reports **leaked-password protection disabled**. Enable it where available in Auth password settings: [Supabase remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). This is an Auth setting, not a SQL change.

## Database and documents

The migrations have been applied to `znxhiymvmluxmdaxzxkt`; filenames match remote history. They depend on the original FYP schema. Do not run them against an empty database or paste them again into this upgraded project.

Credentials use private `provider-documents`. Future provider upload code must use the proper user-owned folder and store the object path in `provider_certifications.file_url`. An MFA-verified admin can request a 60-second signed link. Provider approval requires licence information or a verified, current credential; the administrator must assess the supplied evidence. Existing external/public credential URLs are not automatically copied into private storage.

Category icons use `category-icons`, with content/MIME, size and dimension validation. Profile-image writes are restricted by ownership.

Store credential references as `provider-documents/<auth-user-id>/<unique-filename>`, including the bucket prefix expected by the admin document RPC. The Storage upload object path itself starts at `<auth-user-id>/...` inside that bucket.

## Reports and integrations

Booking CSV and **Print / Save PDF** include all filtered records, up to 10,000. On the report page choose **Print / Save PDF**, then your browser's **Save as PDF** destination. A4 landscape styling repeats headers and handles Unicode names through browser fonts. This is browser PDF output, not a server-generated PDF endpoint.

Analytics filter category (including descendants), provider region and provider. Booking-related measures follow these filters. Membership/new registrations and the provider-verification queue are global and labeled. Dates use Malaysia time; financial series use payment timestamps. Gross collected is distinct from net revenue, platform fees and pending refunds.

Admin actions record notifications and queue email in `private.notification_outbox`. No email worker is installed. Refund requests remain `Requested` until a trusted gateway worker processes them; no fake refund/payout success is exposed.

## Deployment

Use supported PHP 8.4 web server/PHP-FPM with HTTPS and document root `admin/public`. The built-in server is local development only. Set `APP_ENV=production`, HTTPS `APP_URL`, Supabase URL and publishable key through deployment variables/protected configuration. Protect `admin/var`, which stores sessions and throttle records. Provide backups and appropriate logging/retention.

Sessions expire after 30 minutes idle or eight hours total. Auth tokens are refreshed and administrator membership rechecked. Production cookies are Secure, HttpOnly and SameSite=Lax; forms use CSRF. Tokens stay on the PHP server.

For multiple PHP instances, use shared session/throttle storage. Implement and monitor email/refund workers before promising delivery or funds movement. Mobile payment/booking/AI/scheduling needs its own trusted APIs and tests; broad client writes are intentionally not granted as a shortcut.
