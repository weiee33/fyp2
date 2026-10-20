# Shared mobile sign-in

After the existing launch animation, Home Serve opens the orange customer-style
Login screen. The former portal entry widget remains as a compatibility route for
startup, sign-out and account deletion, but renders the shared login directly.

Registration offers Customer and Provider account types. The choice is sent as
signup intent to the existing Auth provisioning trigger. The trigger creates the
canonical `public.users` role and matching profile; it does not permit admin
signup through mobile metadata. Existing accounts require no migration.

Password login, successful signup with a session, and signup OTP verification all
resolve `account_identity` before entering the app. Navigation uses the database
role, not editable user metadata or the registration choice. A failed identity
lookup or unsupported role clears the new local session. Customer-scoped and
provider-scoped service authorization remain in place.

## Password recovery

The existing `customer-recovery` endpoint name is retained for installed-client
compatibility. Its server-only `customer_recovery_check` now accepts both mobile
roles when the account is active, email-verified, not banned, and has its matching
profile. Admin accounts remain outside the mobile recovery flow. Email/IP rate
limits and restricted function grants are retained.

The mobile recovery service still uses an isolated temporary Auth token. It
validates the canonical mobile role before updating a password, discards failed
temporary sessions, and revokes sessions globally only after a successful password
change. Requesting a code alone does not change the password.

Deployment: apply `20261020150053_unified_mobile_account_recovery.sql`, then deploy
`customer-recovery` with JWT verification enabled. Both are deployed to the linked
project. The migration is compatible with older customer clients.

## Language coverage and validation

Shared login, signup, OTP and recovery use English, Simplified Chinese and Bahasa
Melayu, including role choices and validation. The language selection is available
before login and persists across sign-out. Provider Profile also exposes it.
Previously untranslated provider Home/Profile labels, foreground notification
channel descriptions, and authentication copy are covered. Agent panel controls
subscribe to language changes.

Names, provider-authored service descriptions, reviews, chat messages, AI replies,
addresses, booking references and numeric amounts remain unchanged. External
checkout, operating-system permission prompts and photo pickers follow their own
locale support.

Validation:

- `python3 tool/check_localization.py`: both catalog columns, template slots,
  missing literal keys and fixed display text that bypasses translation.
- `flutter test --no-pub`: includes canonical-role/metadata disagreement,
  unauthorized-role session cleanup, registration payloads, both account
  destinations, OTP routing, and narrow-screen enlarged-text layouts in all
  three languages.
- `node --experimental-strip-types --test supabase/tests/customer_recovery_edge.test.mjs`
- Run `supabase/tests/mobile_auth_recovery_regression.sql` as owner inside
  `BEGIN; ... ROLLBACK;`. It creates synthetic accounts, sends no emails and
  checks signup profiles, role tampering, recovery eligibility and rate limits.
- `flutter test --no-pub --platform chrome test/customer_recovery_web_test.dart`
  checks that temporary recovery tokens cannot replace another browser tab's
  active session.

Optional auth screenshots:

```sh
flutter test test/mobile_auth_test.dart --dart-define=CAPTURE_UI=true --dart-define=FLUTTER_FONT_ROOT=<flutter-sdk>/bin/cache/artifacts/material_fonts
```

Screenshots are written under the ignored `.tools/customer-ui/` directory.
