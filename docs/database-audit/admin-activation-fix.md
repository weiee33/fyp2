# Administrator activation repair — 2 October 2026 (Malaysia time)

The email OTP succeeded. The error occurred during the next operation, `admin_identity`, which accepts the invitation and creates the application administrator profile. Supabase Auth had already confirmed the email in a separate transaction. Rolling back application-profile activation does not undo that confirmation or remove the Auth account.

## Root cause and correction

The previous `private.accept_admin_invitation()` inserted `users` and `admin_profiles`, then called the STABLE `private.admin_actor(false)` inside its final SELECT. On a first invocation that authorizer could not see the newly inserted profile and raised SQLSTATE 42501, "An active administrator account is required". The entire activation transaction rolled back, leaving the confirmed Auth account and an unused invitation.

Both the real account and a fresh synthetic invitation reproduced the error. The existing 162-assertion suite passed incorrectly for this scenario because it exercised existing administrators before the first-invitation case. The new standalone regression reproduced the failure against the old function before applying the fix. PostgreSQL documents the relevant [function volatility and snapshot visibility rules](https://www.postgresql.org/docs/17/xfunc-volatility.html).

Migration `20261001151919_admin_activation_snapshot_fix` retains the checks for verified email, unused invitation, active administrator membership and separation from customer/provider accounts. The final query uses the already-authorized local user ID and checks its Auth link, role and active status instead of invoking the STABLE helper after insertion. Existing administrator authorization and all AAL2 gates remain in place.

The PHP email-code flow now clears consumed verification state once Auth succeeds. If subsequent administrator activation fails, it clears the saved authentication session and redirects to password sign-in with an explicit "Your email is verified" message. Invalid/expired email codes still remain on the verification page. This improves error recovery; it grants no additional privileges.

## Live account repair

The project owner's selected email, `angethan765@gmail.com`, was already confirmed by Supabase Auth. Calling the corrected invitation function in a database session scoped to that existing identity completed its authorized Super Admin invitation. The profile is active, linked to the Auth user, and has no customer profile. The repair did not set a password, confirm an email, enroll an authenticator or create an AAL2 session.

The owner should now **sign in with the existing password and complete authenticator setup**. Registration and email verification need not be repeated. The independent customer account remains active with its customer profile.

A separate existing test record, `admin@example.test`, had role `admin` but only a customer profile, no admin invitation and an unconfirmed Auth account. A conditional data correction restored role `customer` only while all those conditions still held. No record was deleted or granted admin privileges. The role/profile mismatch count is now zero.

## Verification

- Standalone first-activation regression: 5 checks passed; it failed with the reported 42501 error before the fix.
- Existing SQL regression suites: 162 assertions passed, with test fixtures rolled back.
- PHP HTTP regression suite: 51 tests passed, including successful email verification followed by rejected activation, cleared session state, retry through password login and continued MFA enforcement.
- All 16 PHP files passed syntax checks.
- All 30 public tables have RLS enabled. Both canonical Auth triggers are enabled.
- All 58 foreign-key relationships across public/private tables were checked against current data: zero orphan relationships. No unvalidated constraints or invalid indexes were found.
- No synthetic `example.invalid` Auth accounts remain. Live admin AAL1 access to administrative data is denied until authenticator verification.

These checks establish database behavior and PHP HTTP contracts. The owner still needs to complete the real authenticator enrollment/login; no real MFA code was collected or used. Flutter was not changed in this repair, and previously documented unfinished payment, booking and AI integrations remain unfinished.

## Remaining advisor notices

The intentional pre-login invitation eligibility RPC is flagged as an [anonymous SECURITY DEFINER endpoint](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) and by the authenticated equivalent. It exposes eligibility only and never grants a role. Private invitations/outbox intentionally have no client policies. Performance notices concern unused indexes in the small development dataset, not missing foreign-key indexes. [Leaked-password protection remains disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection); this is a separate Auth configuration setting, not the cause of the OTP incident.
