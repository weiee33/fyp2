# Customer integration, 3 October 2026

The customer's path is request → provider acceptance → FPX payment → service completion → review. AI is deferred. The orange/white customer UI remains, and administrator login stays on the separate PHP website.

## Modules and integration

| Module | Implemented behavior |
|---|---|
| 5 Profile | Canonical Auth/application identity mapping; atomic name, phone, preferences and photo updates; owned avatar paths; saved address management with an atomic default; address deletion preserves booking snapshots. |
| 6 Discovery | Search/category/city/price/rating filters and pagination through safe projections. Only active services and verified active providers appear. Private licences and credential documents are excluded. Hourly estimates use rate × scheduled duration. |
| 7 Booking | Working hours use Monday=0 and Malaysia time. Duration-aware slot availability, conflicting reservation rejection, idempotent request retry, owned saved address, server-derived price, booking history/detail/cancellation and support requests. |
| 8 Payment | Authenticated Stripe FPX test Checkout; provider acceptance required on the server. Signed callbacks alone record money received. Amount/currency/session checks, event deduplication, retry-safe checkout, stored receipts and late-payment refund review. No simulated Success or escrow claim. |
| 9 Reviews | One review per owned completed, successfully paid booking. Provider identity comes from the booking. Private images have ownership/type/size restrictions; My Reviews obtains temporary signed URLs. Provider ratings update transactionally. |
| 10 Notifications | Booking/payment/progress events share the booking identity. Persistent read state and dismissal; grouped booking filters; booking deep links; Realtime/resume refresh with manual refresh fallback. |

Provider booking list/detail uses guarded RPCs. Accept/decline reports real errors, decline saves the typed reason, and start/completion requires verified payment. Start is allowed no earlier than one hour before the scheduled appointment. The former nonfunctional notification-based chat action is removed from this booking screen; a proper two-way chat system is separate work.

## Additional implementation rules beyond the prototypes

- Each provider currently has capacity for one overlapping appointment. A multi-employee provider needs an explicit staff/capacity model before increasing this.
- Customers can hold at most five pending requests. Requests expire after 24 hours or 30 minutes before the appointment, whichever occurs first. Accepted requests have a 30-minute payment window; starting checkout reserves 31 minutes plus a two-minute callback margin. Expired holds no longer block slots, even if the historical status remains Pending/Confirmed.
- New appointments are at least one hour ahead and at most 90 days ahead. Candidate starts use 30-minute increments; service duration can be longer.
- Booking request IDs and checkout idempotency keys prevent repeat submissions from creating duplicates. Database advisory locks serialize reservations for the same provider. Prices, addresses and service/provider names are snapshotted. Old records were backfilled from the current service catalogue; this cannot reconstruct old names or prices that were never stored.
- Paid cancellations and late payments create administrator refund reviews. They do not transfer money or pretend a refund is complete. Stripe FPX is collection, not escrow. Provider payouts and automated refunds are separate work.
- Review images use a new private `review-images` bucket, maximum 5 MiB, JPEG/PNG/WebP. Existing buckets and existing records were not deleted.
- Distance-in-kilometres filtering is not claimed: provider coordinates are absent from the current schema. City/region filtering is implemented. Map lookup failures allow manual address entry; the user must place the pin at the actual service location.
- Temporary network errors no longer invalidate a valid customer session. Android has Internet permission in the main manifest and Maps metadata under the application element. The embedded AI credential was removed; AI will need a server-side integration later.

## Live deployment

Project: `znxhiymvmluxmdaxzxkt`.

Applied migrations:

1. `20261002080447_customer_module_integration.sql`
2. `20261002081658_customer_fpx_checkout.sql`
3. `20261003045612_customer_checkout_recovery.sql`

The third migration also restores limited column grants after a live check found broad INSERT/SELECT/UPDATE grants on users and provider profiles. Direct verification confirms customers cannot read password hashes, change roles, change provider verification, or call payment writers. Do not resolve client integration errors by granting all table access.

Functions `customer-checkout`, `fpx-webhook`, and `payment-return` are deployed. Checkout requires a valid JWT and checks the user. Webhook uses Stripe HMAC authentication instead of Supabase JWT. The return page uses an expiring purpose-specific HMAC link and grants no access to account data.

## Validation and remaining configuration

- 23 Flutter tests passed, including Pixel 3a-sized state/checkout/receipt screens and existing Auth contracts.
- 51 PHP HTTP regression tests passed.
- 18 Node gateway tests passed: signature tampering/expiry, live-key rejection, server amounts, stable retries, definite-vs-unknown creation failures, and non-acknowledgement of failed database writes.
- Seven SQL suites passed in the migration transaction; all synthetic users/bookings/payments/reviews were rolled back. They include cross-customer isolation, approval-before-payment, overlapping slots, duplicate/late callbacks, receipts, cancellation/disputes, review eligibility and the prior admin regressions.
- Flutter analysis has no errors or warnings; informational style/deprecation findings remain. A debug Android APK was built. These checks do not replace a real-device acceptance test or a real Stripe sandbox checkout.
- A Stripe account, test secret and webhook signing secret are still required; follow [FPX setup](fpx-test-setup.md). Live bank payments have not been tested or enabled.
- Background FCM push, email delivery and notification preferences need Firebase/provider configuration and a delivery worker. Events are persisted in-app and queued; this pass does not claim delivery when the app is closed. No Firebase project configuration was available.
- Supabase security advisor still reports the deliberate pre-login `admin_registration_check` SECURITY DEFINER API and disabled leaked-password protection. Private operational tables deliberately have no client RLS policies. See [public definer guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [private table guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance findings were informational unused indexes; do not drop new reservation/foreign-key indexes based on an empty development workload.

## Repeat checks

```powershell
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos
flutter build apk --debug --no-pub
node --experimental-strip-types --test supabase/tests/fpx_edge.test.mjs
.\.tools\php\php.exe -d "extension_dir=$PWD/.tools/php/ext" admin/tests/run.php
```

For SQL tests, use an owner connection and a single transaction: BEGIN, then `admin_regression.sql`, `policy_indexes_regression.sql`, `analytics_regression.sql`, `auth_customer_regression.sql`, `customer_modules_regression.sql`, `customer_fpx_regression.sql`, `customer_isolation_regression.sql`, then **ROLLBACK**. Never commit test fixtures. Migration files upgrade the existing schema; they are not a blank-project bootstrap.
