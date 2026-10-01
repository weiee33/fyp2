# Admin database verification

The suite in `supabase/tests/admin_regression.sql` tests behavior against the existing database schema upgraded by all five installed migrations. `policy_indexes_regression.sql` verifies the follow-up policy consolidation and private FK indexes; `analytics_regression.sql` verifies filtered analytics. These suites are fail-fast: an unexpected permission, rejected legitimate action, accepted forbidden action, or incorrect stored result raises an exception.

## Execution safety

Run the SQL as the database owner in one transaction and always roll it back:

```sql
BEGIN;
-- Include supabase/migrations/20261001025040_admin_foundation.sql only when testing before installation.
-- Include candidate follow-up migrations only when testing before their installation.
-- Include supabase/tests/admin_regression.sql.
-- Include supabase/tests/policy_indexes_regression.sql.
-- Include supabase/tests/analytics_regression.sql.
-- Include supabase/tests/auth_customer_regression.sql.
ROLLBACK;
```

The installed migrations are:

1. `supabase/migrations/20261001025040_admin_foundation.sql`
2. `supabase/migrations/20261001031048_admin_policy_indexes.sql`
3. `supabase/migrations/20261001031124_admin_analytics_filters.sql`
4. `supabase/migrations/20261001082841_auth_customer_integrity_repair.sql`
5. `supabase/migrations/20261001123803_customer_rpc_boundaries.sql`

When testing the already-upgraded remote database, include **only** `BEGIN`, the four test files in the order shown above, and `ROLLBACK`; do not replay installed migrations. For a pre-installation trial, include the missing candidate migration files before the tests. The foundation is an additive migration against the existing FYP schema, rather than a complete empty-database bootstrap.

The migration and tests must be submitted in the same database session, or as one SQL batch when using the Supabase connector. A failed batch aborts its transaction; roll back the failed transaction before retrying in the same session. Never replace `ROLLBACK` with `COMMIT`. The fixture email addresses use the reserved `example.invalid` domain. The fixture Auth rows, profiles, credentials, payments, refunds, reviews, notifications, audit records and test helpers exist only inside the transaction. The suite never calls the Auth email API, a payment gateway, or a Storage HTTP endpoint.

The SQL impersonates client database roles and JWT claims. This verifies database authorization logic; it does not establish an actual Auth session or prove that the PHP login flow produces an AAL2 token.

## Assertions

- Anonymous clients cannot invoke the admin API. Customers and providers cannot invoke privileged public or private admin functions.
- The Auth signup trigger ignores an injected administrator role in user-editable metadata while permitting ordinary provider registration.
- A verified reserved invitation creates an administrator profile exactly once, without converting existing mobile accounts. AAL2 remains required before administrative data access.
- Staff without AAL2 cannot read or mutate admin resources. Staff with AAL2 can perform permitted operations but cannot view the audit log or request refunds.
- Application user IDs differing from Auth IDs retain correct customer/provider ownership. Other users' data and suspended users' actions remain protected.
- Provider suspension, rejection and category deactivation remove services from actual marketplace reads. Verified active providers and services remain discoverable by anonymous visitors and ordinary customers.
- Private credential path lookup requires an administrator with AAL2 and returns the private bucket object path.
- Password hashes, roles, Auth linkage, account activity, internal authorizers and internal notification writers are inaccessible to ordinary clients.
- Public administration responses omit legacy password hashes.
- Malformed JSON, omitted/null choices, stale row versions, and invalid pagination fail instead of silently applying changes.
- Category cycles, self-parenting, case-insensitive sibling duplication, deactivation of parents with active children, and deletion of categories in use are rejected. An unused category can be deleted.
- Expired credentials cannot be approved; existing expired verification can be revoked.
- Administrative booking confirmation requires a successful payment. Invalid booking transitions are rejected. History records the responsible application user and action reason.
- Cancellation preserves payment collection state until a separate refund action occurs.
- Disputes permit only one active case per booking, enforce valid transitions, and record the closure reason and responsible administrator. The database rejects a resolved case with a null resolution.
- Refunds require a successful payment, a Super Admin, valid decimal precision and an amount within the remaining collected funds. Only one pending refund is permitted and prior successful refunds reduce the remaining amount.
- Review moderation changes visible rating aggregates. Deleting reviews recalculates the aggregate and resets it to zero when the last review disappears.
- Notification delivery is queued honestly and audit records omit legacy credential hashes.

The policy follow-up suite checks actual index definitions, one permissive SELECT policy for each API role/table, continued restrictive active-account guards, an unverified provider's access to its own service and denial after suspension.

The analytics suite verifies two-date call compatibility, a single exposed signature, optional category/provider/region filters, parent-category descendants, actual filter choices, AAL2 authorization, inclusive Kuala Lumpur midnight and exclusive next-day boundaries, zero-filled days, receipt dates for older bookings, Success/Refunded collection versus Pending/Failed exclusion, category popularity, fee/refund/review/dispute attribution and explicitly global user-registration metrics. Analytics fixtures use fixed historical dates inside isolated synthetic categories and are rolled back with the foundation fixtures.

## Analytics API contract

`public.admin_analytics(date_from date, date_to date, category_filter uuid DEFAULT NULL, region_filter text DEFAULT NULL, provider_filter uuid DEFAULT NULL)` is the only public analytics overload. Existing calls with two date arguments remain valid. The PHP GET parameters `category_id`, `region`, and `provider_id` map to the three optional RPC parameters.

The response retains existing dashboard metrics and adds `daily[].gross_collected`, `categories` popularity rows, `category_choices`, `region_choices`, `provider_choices`, `selected_filters`, `global_metrics`, and `scope_note`. Choices come from actual catalogue/provider records. A parent category selects its descendants. Provider region and service category refer to their current profile/catalogue values; the original schema does not snapshot those classifications onto bookings.

Bookings are counted by creation date, while gross collected follows successful payment receipt dates and includes historically collected payments later marked Refunded. It excludes Pending/Failed payments and is not net revenue. The daily series uses inclusive local start and exclusive next-day end in `Asia/Kuala_Lumpur`. User counts/registrations and the pending-provider verification queue remain explicitly global. Current active bookings and unresolved moderation/dispute queues use matching booking dimensions across all dates.

## Recorded verification

On 2026-10-01, the policy/index and analytics candidates compiled against the remote foundation in a rolled-back transaction. All 130 assertions passed: 104 foundation checks and 26 analytics checks. A separate read confirmed zero synthetic Auth/application users, no persisted candidate indexes and the original live two-date analytics signature after rollback. `regression-candidate.json` records this pre-application result. The six additional policy/index assertions bring the full three-file suite to 136; record its separate execution result when run.

## Additional verification outside this SQL suite

Concurrency requires two database sessions: concurrently move category ancestors, request refunds for one payment, and mutate one record from two versions. The row/advisory locks and version guard should permit a consistent outcome without over-refund or lost edits. A single-transaction regression suite cannot prove inter-session locking behavior.

The PHP/browser tests must separately exercise login, MFA enrollment/challenge, session expiry, CSRF rejection, escaped output, search/detail/edit forms, private document signing, category icon upload, filtering/pagination and CSV formula neutralization. Auth rate limits, real email delivery and eventual payment-gateway integration need their own configured environment.

The complete suite was subsequently executed against all three applied migrations on 2026-10-01: **136 passed**, followed by `ROLLBACK`. The isolated PHP HTTP suite passed **45 checks** with no PHP warnings/fatal errors. `verification.json` records the installed revisions, results, browser checks and remaining integration limits.
