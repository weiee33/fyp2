# Admin website setup

## Windows development

The mobile environment remains Flutter 3.38.8 / Dart 3.10.7, Android Studio 2025.2.3.9 on Windows 64-bit, and the Pixel 3a emulator. Those tools do not execute PHP. Open `fyp2` in Android Studio and run the separate PHP server from its PowerShell terminal; use a browser for the admin website.

`scripts/Setup-AdminRuntime.ps1` installs PHP 8.4.27 NTS x64 into ignored `.tools/php`, verifies the official archive SHA-256, and enables cURL, OpenSSL, mbstring and fileinfo. No Composer or JavaScript build is required; XAMPP and system PATH remain independent.

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

## Administrator access

Existing administrators sign in with their email, password and authenticator code. A Super Admin can invite colleagues from **Admin team**; follow the invitation guide below. Customer and provider accounts cannot be converted into administrators through this flow.

1. The recipient opens the shared activation link and creates a password using the exact invited email.
2. They enter the numeric email verification code from Supabase Auth. Activation checks the invitation, expiry and verified email before creating the admin profile.
3. They set up an authenticator and verify its current six-digit code. All administrative data and actions require MFA (AAL2).
4. Later sign-ins use email/password followed by an authenticator code.

If a project has no Super Admin yet, its trusted database owner must reserve the first unused admin email in `private.admin_invitations` with `role_level='super_admin'`. This is a one-time bootstrap; subsequent invitations belong in the dashboard. Never derive privileges from signup metadata or reuse a customer/provider email.

If email verification succeeds but activation fails, sign in with the existing password after the invitation issue is fixed. Do not reuse the consumed email code or create a duplicate account. Password recovery also requires the authenticator. Lost-authenticator recovery needs a trusted project-owner process; the portal provides no MFA bypass.

## Auth settings

SQL cannot configure Auth URL settings. In [project Auth URL Configuration](https://supabase.com/dashboard/project/znxhiymvmluxmdaxzxkt/auth/url-configuration), add `http://127.0.0.1:8088/?page=callback` to the redirect allowlist. Use `http://127.0.0.1:8088` as Site URL for an admin-only development environment. Preserve the primary Site URL if another app depends on it; this website explicitly requests its admin callback. Keep existing needed allowlist entries.

In **Authentication → Emails → Confirm signup**, ensure the template includes `{{ .Token }}`. A ready-to-copy template is saved in `supabase/templates/confirm-signup.html`. The email code can be entered by both the customer app and the admin website; do not disable global email confirmation to work around registration errors. Keep TOTP enrollment/verification enabled under **Multi-Factor**. Email code entry does not require an Auth callback redirect, but email-link confirmation and password recovery do.

Check the template if an email contains only a link; use **Send a new code** after saving changes. Auth email delivery and SMTP configuration are separate from shareable invitation links. Local fixture tests do not establish live email delivery.

Configure production URLs separately. Email confirmation/recovery uses Supabase Auth email configuration. Configure SMTP for reliable delivery and check Auth email/rate limits. Real email delivery/redirects are not established by stub tests.

The advisor reports **leaked-password protection disabled**. Enable it where available in Auth password settings: [Supabase remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). This is an Auth setting, not a SQL change.

## Database and documents

The migrations have been applied to `znxhiymvmluxmdaxzxkt`; filenames match remote history. They depend on the original FYP schema. Do not run them against an empty database or paste them again into this upgraded project.

Credentials use the private `certifications` bucket. Provider uploads use a user-owned folder and store the object reference in `provider_certifications.file_url`. An MFA-verified admin can request a 60-second signed link. Provider approval requires licence information or a verified, current credential; the administrator must assess the supplied evidence. Existing external/public credential URLs are not automatically copied into private storage.

Category icons use `category-icons`, with content/MIME, size and dimension validation. Profile-image writes are restricted by ownership.

Store credential references as `certifications/<auth-user-id>/<unique-filename>`, including the bucket prefix expected by the admin document RPC. The Storage upload object path itself starts at `<auth-user-id>/...` inside that bucket.

## Reports and integrations

Booking CSV and **Print / Save PDF** include all filtered records, up to 10,000. On the report page choose **Print / Save PDF**, then your browser's **Save as PDF** destination. A4 landscape styling repeats headers and handles Unicode names through browser fonts. This is browser PDF output, not a server-generated PDF endpoint.

Analytics filter category (including descendants), provider region and provider. Booking-related measures follow these filters. Membership/new registrations and the provider-verification queue are global and labeled. Dates use Malaysia time; financial series use payment timestamps. Gross collected is distinct from net revenue, platform fees and pending refunds.

Admin actions record in-app notifications. The legacy `private.notification_outbox` is separate from the current customer delivery worker; do not assume that every admin action sends email. Customer push and receipt-email delivery are documented in [customer alerts and receipts](customer-alerts-and-receipts.md). Refund requests remain `Requested` until a trusted gateway worker processes them; no fake refund/payout success is exposed.

## Deployment

Use supported PHP 8.4 web server/PHP-FPM with HTTPS and document root `admin/public`. The built-in server is local development only. Set `APP_ENV=production`, HTTPS `APP_URL`, Supabase URL and publishable key through deployment variables/protected configuration. Protect `admin/var`, which stores sessions and throttle records. Provide backups and appropriate logging/retention.

Sessions expire after 30 minutes idle or eight hours total. Auth tokens are refreshed and administrator membership rechecked. Production cookies are Secure, HttpOnly and SameSite=Lax; forms use CSRF. Tokens stay on the PHP server.

For multiple PHP instances, use shared session/throttle storage. Implement and monitor email/refund workers before promising delivery or funds movement. Customer booking, payment and AI use trusted APIs; see the main README for the current module guides. Broad client writes are not granted as a shortcut.

## Invite another administrator

Sign in as a Super Admin, complete MFA, then open **Admin team**. Enter an unused email, select Staff Admin (normal operations) or Super Admin (also invitations, audit and refund requests), and create the invitation. Copy the activation link and share it with the intended person. This creates authorization, not an email; signup verification emails still come from Supabase Auth.

New invitations expire after seven days. Renew extends the invitation for seven days; revoke prevents unused activation. Accepted invitations cannot be renewed or revoked, and existing customer/provider accounts cannot be converted. Changes are checked in the database and recorded in the audit trail. Existing setup invitations retain their prior expiry behavior until renewed.

The recipient opens the link, uses the invited email, creates a password, verifies the email code and enrolls an authenticator. A localhost link works only on the computer running PHP: use the deployed HTTPS `APP_URL` for colleagues on other devices. Do not publish the development server.
