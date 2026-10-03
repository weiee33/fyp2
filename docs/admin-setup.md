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

## First Super Admin (updated 3 October 2026)

Current check: `angethan765@gmail.com` is an active, confirmed Super Admin with one verified authenticator. Use Sign in and the existing authenticator code. The password supplied by the owner was successfully tested during the investigation; this work did not set or reset it. The old reference `a4104ca7` was not present in the available local logs, so its original cause could not be established. PHP now logs a sanitized source location alongside future error references.

The reserved admin email is **angethan765@gmail.com**. **weiee0303@gmail.com remains a customer** and its obsolete admin invitation is revoked. The selected admin has now confirmed its email and has an active, linked Super Admin profile. Start at **Sign in** with the existing password, then complete authenticator setup. Do not register again, delete the Auth account, or reuse the consumed email code. No password or email-confirmation flag was changed by the repair.

1. For the existing confirmed account, open `http://127.0.0.1:8088/?page=login` and sign in, then continue at step 3. For a genuinely new invited account, start at **Activate your admin account** and create a password. Only an unconfirmed account should use **Send a new code** on the email-verification page.
2. Enter the numeric **email verification code** on this page. The server validates it with Supabase Auth, accepts the reserved invitation and creates the admin profile. Wrong/expired codes cannot open the dashboard.
3. On **Protect your account**, choose **Set up authenticator**. Scan the QR code with an authenticator app (or use the displayed setup key), then enter its current **six-digit authenticator code**.
4. Subsequent logins use email/password followed by the authenticator code. Email confirmation is a one-time activation step; it does not replace MFA. Database admin operations require AAL2.

A login attempt for an unconfirmed admin account routes to the email verification page. A fresh signup is checked against the invitation list before calling Auth. Neither metadata nor a mobile customer/provider profile can grant admin rights. The project owner must reserve any additional admin email in `private.admin_invitations`; the public website cannot grant invitations.

If email verification succeeds but profile activation subsequently fails, the website returns to sign-in with a message explaining that the email is already verified. After the invitation/backend issue is repaired, password sign-in retries activation. Auth users exist before confirmation; an Auth row alone does not grant administrator access. See the [activation incident and verification report](database-audit/admin-activation-fix.md).

If the password is unavailable, configure the callback below and use **Forgot password?** after email activation. Recovery requires the administrator's authenticator before choosing a new password. Lost-authenticator recovery needs a trusted project-owner process; the portal provides no MFA bypass. Keep passwords, QR setup keys and codes private.

## Auth settings

SQL cannot configure Auth URL settings. In [project Auth URL Configuration](https://supabase.com/dashboard/project/znxhiymvmluxmdaxzxkt/auth/url-configuration), add `http://127.0.0.1:8088/?page=callback` to the redirect allowlist. Use `http://127.0.0.1:8088` as Site URL for an admin-only development environment. Preserve the primary Site URL if another app depends on it; this website explicitly requests its admin callback. Keep existing needed allowlist entries.

In **Authentication → Emails → Confirm signup**, ensure the template includes `{{ .Token }}`. A ready-to-copy template is saved in `supabase/templates/confirm-signup.html`. The email code can be entered by both the customer app and the admin website; do not disable global email confirmation to work around registration errors. Keep TOTP enrollment/verification enabled under **Multi-Factor**. Email code entry does not require an Auth callback redirect, but email-link confirmation and password recovery do.

The dashboard browser was signed out during this repair, so the current template, SMTP and redirect allowlist could not be verified or changed. Connector SQL access does not provide these Auth settings. Check the template if an email contains only a link; use **Send a new code** after saving changes. This is configuration still requiring verification, not a claimed completed live email test.

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
