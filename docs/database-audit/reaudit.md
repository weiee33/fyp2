# Schema and authentication re-audit — 1 October 2026

Reviewed live metadata for all 30 public and two private tables: columns/defaults/nullability, primary/foreign/unique/check constraints, indexes, RLS policies, grants, functions and triggers. `reaudit-before.json` records the live definitions. The three recorded migrations did not include the subsequent SQL Editor changes; the live schema was therefore not equivalent to the repository migrations.

## Findings before changes

1. **Critical:** the replacement `handle_new_user` trigger accepted `admin` from editable signup metadata and omitted `auth_user_id`. One customer profile had a null Auth link. Two Auth accounts had no application profile.
2. **High:** an unused invitation still targeted the email now used as a customer. An invitation must not silently convert an established customer/provider account into an administrator.
3. **High:** customer/provider login used editable metadata before the database role; OTP verification did not validate the application role.
4. **High:** added permissive policies overlapped the original ownership policies. Their names promised restrictions (such as pending-only cancellation) that their expressions did not enforce. Table grants still prevented most new writes, so adding policies alone did not make the mobile operations work.
5. **High:** saved-address changes required several independent requests, lacked write grants, and could leave multiple defaults or a stale header address. Use an ownership-checked transactional operation rather than granting arbitrary profile writes.
6. **High:** independent FKs allowed a booking to reference another provider's service, a payment/review to name the wrong customer, or earnings to name the wrong provider. There were no inconsistent rows in the live preflight, but these combinations were not prevented.
7. **Medium:** review aggregates ran twice per mutation because two triggers existed. Keep the canonical trigger, which handles DELETE and both providers on UPDATE.
8. **Medium:** positive duration, working-hour ordering, earnings uniqueness and fee bounds were missing.
9. **High:** provider discovery joined private user records, then replaced permission errors/empty results with fictional providers, ratings and AI matches. Permission failures must remain visible; discovery should expose only a deliberately limited projection.
10. **Admin flow:** signup requested email confirmation but had no email OTP entry page. Authenticator MFA already had a code field, but could not be reached while email confirmation/profile activation failed. Preserve both email verification and AAL2 authorization.

## Table-by-table disposition

| Tables | Review result / action |
|---|---|
| users | Repair identity mapping and authoritative role lookup; Auth owns passwords/email confirmation. Legacy unlinked seed rows are preserved and cannot sign in. |
| customer_profiles, admin_profiles, provider_profiles | One profile per user is enforced. Correct signup child creation; reserved admin activation must not convert customer/provider profiles. Add nonnegative provider metrics. |
| saved_addresses | Ownership-checked atomic RPC and one-default partial unique index. |
| services, service_categories, category_fields | Existing category FKs and guarded admin hierarchy retained. Add positive duration; field definitions still need a typed mobile submission contract. |
| provider_working_hours | Existing provider/day uniqueness retained; require end after start (same-day intervals). |
| provider_certifications, provider_portfolio | Provider FKs retained; credential verification remains admin-only and documents private. Provider editing/upload integration remains separately tracked. |
| bookings, booking_status_history | Enforce service/provider consistency; existing admin transitions/history retained. Mobile reservation capacity, customer completion acceptance and payment sequencing remain unimplemented workflows. |
| payments, provider_earnings | Enforce matching booking parties, unique earnings per booking and fee bounds. Gateway webhooks, retries/idempotency and settlement still require backend implementation. Pending payment_timestamp is legacy and must not be treated as proof of payment. |
| reviews | Enforce matching booking parties; remove duplicate rating trigger. Customer review submission still needs a completed-booking transaction; direct client inserts remain denied. |
| booking_disputes, refund_requests | Existing attributed resolution, open-request uniqueness and guarded refund caps retained. Actual gateway refund execution remains external work. |
| notifications, private.notification_outbox | Existing ownership/read-state restrictions and transactional enqueue retained. Delivery worker and token lifecycle remain unfinished. |
| ai_job_matches, ai_provider_recommendations, ai_recommendations | Individual FKs exist; scoring scales, versioning, freshness and reproducibility still need an implemented engine contract. Do not present placeholder scores as predictions. |
| ai_schedules | Provider/date identity exists; booking_ids is an array without element FKs. Normalize scheduled jobs and enforce capacity before implementing optimizer writes. |
| chatbot_sessions, chatbot_messages | Ownership FKs exist. Current permissive client-write policies are removed; a trusted, rate-limited AI persistence path remains to implement. |
| analytics_snapshots, provider_performance | Reporting FKs retained. Define snapshot generation and non-overlapping aggregation periods before background generation. |
| audit_logs, user_account_actions | Protected admin attribution retained. Arbitrary client writes remain denied. |
| otp_verifications | Legacy application OTP storage is not used. Supabase Auth verifies codes; this table receives no client grants. |
| private.admin_invitations | Revoke obsolete customer invitation, reserve the separately selected admin email, and require verified ownership before activation. |

## Limits

This audit does not certify every future mobile/payment/AI workflow as implemented. No account passwords, OTP secrets or business rows are included in the metadata snapshot. No existing account is deleted or automatically email-confirmed. Real email delivery and a real authenticator login require the account owner to enter their private codes.

## Applied repairs and verification

Remote migration versions: `20261001082841_auth_customer_integrity_repair` and `20261001123803_customer_rpc_boundaries`. The repository filenames match the Supabase history. Regression fixtures execute inside a savepoint and are rolled back; failing assertions prevent the migration from committing. A separate transaction replay passed 162 SQL assertions. No fixture Auth accounts remain.

The selected customer is active, remains a customer and has a valid Auth link. A database session using that customer's actual identity can read exactly one own customer profile. The selected admin has an unused Super Admin invitation and an unconfirmed Auth account; activation still requires the account owner's email code and authenticator. A real PostgREST call confirms that this admin email passes the registration eligibility check. No passwords, email codes or authenticator secrets were collected.

New client RPCs use public invoker wrappers around private implementations with explicit identity checks. Address mutations lock the customer row, preventing concurrent default-address changes from leaving multiple defaults. Composite FK indexes were added; the final performance advisor reports unused-index notices only, expected for tables without workload.

The public `admin_registration_check` is deliberately callable before login and returns only eligibility, never profile data or a role grant. It is therefore flagged by the [anonymous definer-function advisor](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) (and its authenticated equivalent). The PHP form rate-limits requests; the public RPC itself remains enumerable as an eligibility boolean. Registration/activation still requires verified ownership and a private invitation. Private invitations/outbox intentionally have no client table policies. [Leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains disabled in Auth settings.

Flutter contract tests cover password/OTP role enforcement, local-session cleanup, atomic address API contracts and truthful directory failure/empty states. The Pixel 3a-sized entry test verifies customer/provider portals only. Static analysis reports no errors or warnings; existing informational deprecation/style notices remain. The test harness replaces the obsolete counter-app test and runs in GitHub Actions.

Additional work introduced by this repair: explicit email OTP entry/resend, registration eligibility checks, email-confirmation synchronization, database role checks after mobile OTP, atomic default addresses, cross-table participant constraints, limited provider discovery and automated regression coverage. These supplement the original report design. Mobile booking/payment/AI features are not claimed complete. The later customer commit `d77f289` is incorporated and reviewed in [latest customer integration findings](../customer-latest-integration-review.md); its additional screens still require the trusted backend operations described there.
