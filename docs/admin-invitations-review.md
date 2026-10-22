# Admin invitations and integration review

Verified on 22 October 2026. This pass adds invitation management and checks the existing admin/customer workflows; it does not claim that every possible production scenario has been exercised.

## Delivered

- Super Admins with MFA can create, search, renew and revoke unused invitations from **Admin team**. Staff, customers, providers and anonymous users are denied by the database as well as the website.
- Shareable activation links use the configured `APP_URL`. The link is not a bearer credential: activation still requires the invited email, email verification and an authenticator. Invitation emails are not sent automatically.
- New invitations expire after seven days. Existing setup invitations keep their previous expiry behavior until renewed. Accepted invitations cannot be changed; existing customer/provider accounts cannot be converted.
- Invitation changes use row locking, stale-version checks and attributed audit records. No direct invitation-table access or service-role credential is granted to the web app.
- Shared confirmation dialogs, reduced-motion support, wrapping buttons, clearer secondary text and keyboard-safe mobile navigation apply across admin modules. Visible branding uses Home Serve.
- Support screens explain that responses are visible in the customer's separate **Support response** card. Booking guidance now reflects provider acceptance before customer payment.
- README and setup instructions cover the three application roles, invitation sharing and deployment limitations. Windows setup now installs verified PHP 8.4.27 and refuses to overwrite a running runtime.

## Validation

| Check | Result |
| --- | --- |
| PHP HTTP workflow suite | 58 passed; local isolated Auth/RPC fixtures |
| PHP syntax | 17 files passed |
| Browser JavaScript syntax | Passed |
| Admin + invitation + customer-support SQL | 166 passed after migration |
| Admin + policies + analytics + auth + customer modules + FPX SQL | 203 passed after migration |
| First activation in a fresh database connection | 5 passed; repeat activation idempotent, MFA still required |
| Windows runtime | PHP 8.4.27 installed; four required extensions loaded; running-runtime guard passed |
| Browser fixture review | Invitation form, confirmation cancel/confirm, narrow layout and navigation focus/escape verified |

SQL suite totals overlap and must not be added together. All SQL fixtures ran within transactions ending in `ROLLBACK`; synthetic invitation cleanup was verified. No real colleague was invited and no real email or payment was sent by these tests. Browser checks used synthetic local data, not a live administrator session. Desktop layout across every viewport and live email delivery remain outside this verification.

Migration `20261022033916_admin_team_invitations.sql` is applied to the configured Supabase project. Its filename matches remote migration history. Do not apply it again there. The PHP website must run this branch's files to expose the new menu.

## Existing operational boundaries

- Colleagues need a deployed HTTPS admin website and public `APP_URL`; a localhost activation link works only on its host computer. Supabase Auth still sends verification codes through its configured email provider.
- Refund requests record a request; they do not transfer money. The legacy admin notification outbox is separate from customer push/receipt delivery.
- Supabase's post-migration security advisor reports the existing public registration-preflight function and disabled leaked-password protection. The preflight intentionally supports unauthenticated activation checks and grants no admin access. See [function execution guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
- Private tables intentionally have RLS with no direct API policies; guarded functions provide access. The new invitation wrappers are security invokers, with authorization in private functions.
- Performance advisories remain on existing provider booking/earnings policies: per-row Auth calls and overlapping earnings read policies. These were not altered by the invitation migration. See [RLS initialization guidance](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan) and [multiple policies](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies).

## Repeat the invitation database checks

Run as the database owner against an upgraded schema:

```sql
BEGIN;
-- Include supabase/tests/admin_regression.sql.
-- Include supabase/tests/admin_invitations_regression.sql.
-- Include supabase/tests/customer_support_regression.sql.
ROLLBACK;
```

Run `admin_first_activation_regression.sql` separately in a fresh connection and rolled-back transaction, before any other admin RPC in that connection. Follow the existing test plan for the broader booking/payment suite.
