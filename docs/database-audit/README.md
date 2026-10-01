# Database audit and corrections

**Latest:** see [1 October re-audit](reaudit.md) for SQL Editor drift, the customer/Auth linkage repair, corrected administrator email, and remaining mobile workflow gaps. The earlier results below describe the first implementation, before those later SQL edits.

Reviewed connected Supabase **FYP Project**, ref `znxhiymvmluxmdaxzxkt`, against both FYP 1 Chapter 4 designs. The original 28 tables cover users, providers, categories/services, bookings, payment/earnings, reviews, notifications, AI, chatbot, analytics and audit. GitHub originally contained a Flutter starter with empty provider files and no SQL/PHP portal.

`before.json` stores original schema/function/policy/grant metadata; `preflight.json` captures additional live policies and the Auth trigger discovered before upgrading. These are schema evidence, not private business-data backups. Migrations preserve existing application rows.

| Finding | Implemented correction |
|---|---|
| User could edit role/account activity | Column-limited normal edits; guarded admin mutations. |
| Signup trusted editable metadata for admin role | Ordinary customer/provider signup only; verified reserved invitations authorize admin activation. |
| App user IDs assumed equal to Auth IDs | Unique explicit `users.auth_user_id` mapping; tests use different IDs. |
| Provider could change own verification | Editable-column grants exclude verification; admin approval records identity/reason. |
| Discovery exposed unverified/suspended providers | Checks verification, account activity and category eligibility. |
| Broad privileges included TRUNCATE | Replaced with limited grants; RLS does not protect TRUNCATE. |
| Duplicate broad policies existed | Removed unsafe overlap; explicit ownership/discovery rules retained. |
| No unified privileged data path | Invoker public RPCs call guarded private functions requiring active membership and AAL2. |
| Storage writes affected other users | Owner/folder restrictions and private credentials with short-lived links. |
| Review DELETE left incorrect ratings | Correct OLD handling, hidden/flagged exclusion, zero when empty. |
| Category hierarchy/history could be corrupted | Locked cycle/duplicate/active-child checks and refusal to delete referenced categories. |
| Booking changes lacked actor/reason | Controlled transitions and attributed history; cancellation preserves payment collection state. |
| No operational disputes/refund records | Attributed disputes and bounded refund requests with active/pending uniqueness. |
| Stale edits silently overwrote records | Row locks and record-version checks. |
| Email delivery untracked | Notifications and outbox commit together; worker remains external work. |
| Mutable function paths/missing FK indexes | Qualified access, execution restrictions, FK indexes and consolidated SELECT policies. |

## Scope

The admin implementation covers both reports' administrative responsibilities. The wider schema does not establish that every mobile flow is ready. Before mobile work, resolve payment versus provider acceptance, customer completion acceptance, refunds/settlement, worker capacity and atomic reservations, job matching versus category advice, and fixed versus flexible scheduling. AI contracts and real payment event processing require implementation.

Legacy `password_hash` is nullable and excluded from responses; Supabase Auth owns passwords. No app data was erased. Live categories/Auth records changed during this collaborative session, so final counts are observations rather than a claimed migration-only count difference.

## Advisors

Function-search-path warnings were removed. Follow-up changes address missing FK indexes and overlapping provider/service SELECT policies. Fresh indexes may remain marked unused without production workload; this is not grounds to drop necessary indexes.

Private `admin_invitations` and `notification_outbox` intentionally have RLS without client policies and no client grants. Trusted functions/workers own access. See [RLS/no-policy advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Leaked-password protection remains an Auth setting: [remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). See [setup](../admin-setup.md) for email/callback configuration.

## Evidence

See [regression plan](test-plan.md), `supabase/tests/admin_regression.sql`, and `admin/tests/README.md`. Tests cover meaningful permissions/business rules and isolated HTTP workflows. They do not prove email delivery, gateway processing, concurrent-session behavior, production deployment or complete mobile acceptance. Executed counts and migration versions are recorded in `verification.json`.
