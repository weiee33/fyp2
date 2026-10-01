# Provider Flutter integration review

Reviewed: 1 October 2026, against remote commit `c6a7946` (`provider part`), including `4982066`, and the applied administrative database foundation in this repository. Flutter files were inspected read-only. No provider screen/service was edited and no real provider booking/payment was changed during this review.

This is a static compatibility review, not a successful end-to-end mobile test. The PHP administrative website has its own validation evidence; that does not establish that the newly added Flutter provider code works against the tightened database permissions.

## Current progress

The new commits contain provider authentication, profile/credential/working-hour/service-area screens, service CRUD, booking/chat views, earnings and notification service code. This is substantive progress beyond the original empty provider files. However, several client assumptions conflict with the shared database and its permission model.

The entry point still goes directly to the provider profile after login (`lib/main.dart:29`, `lib/Provider/screens/auth/login_screen.dart:59`). `provider_home.dart`, the model files, `start_card.dart`, and both AI screens are empty in this commit. Firebase initialization is commented out (`lib/main.dart:14`). These are unfinished scope, not evidence that push or AI generation already operates.

## Shared identity contract

`auth.users.id` identifies a Supabase Auth account. `public.users.user_id` identifies an application profile. The administrative foundation adds `public.users.auth_user_id`, and policies resolve the active application account through that mapping (`supabase/migrations/20261001025040_admin_foundation.sql:6`, `:60`).

The safe signup trigger currently sets **both** IDs to `new.id` for newly registered customers/providers (`20261001025040_admin_foundation.sql:114–128`). Therefore, the provider client's current `user_id == auth.currentUser.id` queries can work for those new accounts. They are not universally broken merely because the mapping column exists. Existing or later linked application profiles may have an independent `user_id`; equality is not the general contract.

For the mobile phase, resolve one authenticated profile/role context by `auth_user_id`, retain the returned application `user_id` and `provider_id`, and use those identifiers consistently. Storage owner folders deliberately continue to use the **Auth ID**.

## Findings requiring the next mobile integration phase

### 1. Profile wildcard selects conflict with protected columns

**Code:** `lib/Provider/services/profile_service.dart:25–35` uses `.select()` on `users` and `provider_profiles`.

**Database:** The foundation grants only explicit safe columns on `users` (`20261001025040_admin_foundation.sql:149`), excluding the legacy password hash. Its provider-profile SELECT grant also excludes business licence, administrative verifier identifiers and rejection fields (`:156`). Wildcard selection asks for those columns too, so these queries are expected to receive a permission error rather than the merged profile.

**Required change:** Use explicit column projections or a narrow own-profile API. If the provider must see their own private licence/rejection details, expose those through an ownership-checked projection rather than granting sensitive columns publicly. The profile editor should never request a password hash.

The update field allowlist includes `verification_status` (`profile_service.dart:54–62`), but the database intentionally does not grant provider permission to update that field (`foundation.sql:162`). Remove it from provider-editable fields. Provider approval belongs to the administrative workflow. The fallback insert (`profile_service.dart:80–85`) is also unavailable under current grants and unnecessary for a normally provisioned provider: the signup trigger already creates a Pending profile.

### 2. Credential upload uses the wrong bucket and visibility contract

**Code:** `lib/Provider/screens/profile/certifications_screen.dart:94–106` uploads to `certifications`, uses a flat timestamp/filename path, and stores a public URL. `profile_service.dart:115–125` always uploads with `upsert: true` and returns `getPublicUrl()`.

**Database:** Preflight contained only the `profiles` bucket. The applied foundation adds **private** `provider-documents` (`foundation.sql:188–191`), with owner uploads restricted to a first folder equal to `auth.uid()`. The administrative document RPC requires stored `file_url` values to start with `provider-documents/` (`:271–274`). Credential Storage policies permit owner INSERT/SELECT; they do not grant credential overwrite/upsert.

**Required change:** Upload a validated PDF/JPEG/PNG to a new unique object path such as `<auth-id>/<unique-document-name>` in `provider-documents`, with the correct content type and `upsert: false`. Store `provider-documents/<auth-id>/<object-name>` as the database reference. Open documents with an authorized signed URL. Keep size/type validation aligned with the 10 MB bucket limits. Replacing or withdrawing an approved credential needs an explicit re-verification/history policy, not an unrestricted overwrite.

The certification metadata column names themselves match the database (`certification_name`, `issuer`, `expiry_date`, `file_url`). The problem is storage/authorization, not a need to rename those fields.

### 3. Direct mobile writes are deliberately unavailable

**Code:**

- `profile_service.dart:140–152`: insert/delete certification records.
- `profile_service.dart:157–162`: upsert working hours.
- `service_service.dart:25–36`: insert/update/archive services.
- `booking_service.dart:45–62`: update booking status and client-generated timestamps.
- `booking_service.dart:75–83`: insert notifications as chat messages.
- `ai_service.dart:28–31`, `:55–64`: update recommendations/upsert schedules.

**Database:** The foundation revokes broad table writes (`foundation.sql:136–155`). Current grants restore only specific safe profile columns and `notifications.is_read` (`:162–163`). Existing ownership policies alone do not supply INSERT/UPDATE privileges. The policy-index migration preserves this distinction; it does not reopen broad writes.

**Required change:** Implement the mobile business APIs and corresponding Flutter integration during the mobile phase. Their actor, ownership, allowed fields, transition rules and validation must be explicit. Provider service/credential/hour operations need narrowly scoped writes or RPCs; booking changes require assigned-provider authorization, server timestamps and agreed lifecycle preconditions. Administrative RPCs are not substitutes for provider RPCs because they require an administrative MFA session.

Do not make these screens “work” by restoring full authenticated write grants. That would reintroduce client control over verification, payments, earnings and booking lifecycle fields.

### 4. Nested customer joins do not satisfy privacy policies

**Code:** `booking_service.dart:21–25`, `:35–38` joins `customer_profiles!inner(users!inner(full_name, phone))`. `earnings_service.dart:69` makes a similar inner join for review author names.

**Database:** Application users can SELECT their own `users` row; customer profiles remain owner-scoped. An assigned provider can have access to a booking without gaining general access to the customer's user/profile tables. Under RLS, these inner joins can filter out otherwise visible bookings/reviews or return no usable embedded customer data.

**Required change:** Provide an authorized booking detail/list projection that returns only the contact details the assigned provider needs for that booking. Public review attribution needs its own privacy-safe projection. Do not widen general user/profile SELECT policies just to satisfy a nested query.

### 5. Chat is currently a sender notification, not a conversation

**Code:** `booking_service.dart:65–83` reads `notifications` with type `Message` and inserts a row whose `user_id` is the sender's Auth ID.

**Consequence:** Apart from the revoked INSERT, the current recipient-owned notification model makes that row visible to its recipient/sender. It does not define a two-party conversation or deliver the message to the customer. The notification schema has no separate conversation participant/sender model.

**Required change:** Introduce booking conversations/messages with explicit sender, authorized participants, sequence/read state and a customer receiving interface. Notifications should alert the other party about an existing message. They should not serve as the sole chat record. Realtime subscriptions and FCM are separate delivery concerns.

### 6. Working-hour saves are not repeatable yet, and weekday labels disagree

**Code:** `working_hours_screen.dart:12–19` labels index `0` as Monday. Saved rows use those indices (`:70–79`). `profile_service.dart:157–162` upserts rows without `working_hour_id` or an `onConflict` target.

**Database:** The table has primary key `working_hour_id` and a unique `(provider_id, day_of_week)` constraint, recorded in `docs/database-audit/before.json`. If writes were enabled unchanged, saving a second set of hours would attempt new primary keys and conflict with the provider/day uniqueness rather than reliably updating the existing week. The database constrains days to `0–6` but does not itself define Monday/Sunday semantics. The administrative view initially labelled `0` as Sunday. It has now been corrected to match the existing provider writer: Monday is `0` and Sunday is `6`. This convention is documented in `docs/admin-modules.md`; no Flutter change was needed for that correction.

**Required change:** Retain the documented Monday-0 convention across mobile, scheduling and tests. Use an ownership-checked atomic seven-day save or explicit composite conflict handling. Validate start/end order, inactive-day rules and treatment of overnight hours. Do not invent default 09:00 working hours when server loading failed.

### 7. AI service targets an absent recommendation contract

**Code:** `ai_service.dart:20–31` expects table `ai_provider_recommendations` with `recommendation_id`, `status` and `match_percentage`.

**Database:** The audited schema has `ai_job_matches` with `match_id`, `booking_id`, `match_score` and factor/explanation columns. The current migrations do not add `ai_provider_recommendations`. This is a concrete table/column mismatch, distinct from revoked write access.

**Required change:** Resolve the FYP 1 ambiguity between actual job matching and category-expansion recommendations before designing the API. Do not simply rename a table without matching its meaning. The current AI screens are empty, and no ranking/optimization execution is implemented by this service file.

`ai_service.dart:55–64` also lacks a `(provider_id, schedule_date)` upsert target, while that composite key is unique. `optimized_score` receives `estimatedEarnings` (`:62`), mixing two different concepts. Scheduling needs server-generated proposals, agreed appointment constraints and safe acceptance; direct client persistence must not bypass them.

### 8. Authentication success does not establish provider eligibility

**Code:** `auth_service.dart:12–16` signs up with provider metadata; `login_screen.dart:53–62` routes any successful Auth sign-in directly to the provider profile. `lib/main.dart:29–31` checks only whether a session exists.

**Database:** Metadata permits a self-service customer/provider choice at account creation; it cannot create an administrator (`foundation.sql:117–124`). An account's active role and provider verification are database properties, not implied by possession of an Auth session.

**Required change:** Add a role-aware active-account gate and explicit Pending/Rejected/Verified provider states. Customers should reach customer routes, and suspended accounts should receive a clear sign-out/access explanation. React to Auth session changes instead of relying only on the initial synchronous session check.

The signup trigger currently initializes `email_verified` at account creation and does not copy `phone` metadata (`foundation.sql:119–124`). Registration passes phone (`auth_service.dart:15`), so it must be saved through a validated allowed profile update or a deliberately reviewed server provisioning path. Auth confirmation and the mirrored application verification field need a synchronization contract; a stale profile Boolean must not override authoritative Auth verification.

### 9. OTP delivery needs a defined email template and resend flow

**Code:** Registration immediately displays `OtpScreen` (`register_screen.dart:71–83`). Resend uses passwordless `signInWithOtp` (`auth_service.dart:31–32`) rather than an explicit registration-confirmation resend. Verification uses `OtpType.email` (`:39–43`).

**Finding:** `OtpType.email` is a current supported email verification type; it should not be “fixed” to a deprecated type on assumption. What remains unverified is whether the project's signup email template delivers an input code or a link, and whether the displayed screen matches that configured flow. Passwordless sign-in may create users by default, which is a different operation from resending signup confirmation. [Supabase Flutter OTP verification](https://supabase.com/docs/reference/dart/auth-verifyotp), [passwordless sign-in](https://supabase.com/docs/reference/dart/auth-signinwithotp)

**Required change:** Select confirmation-link or email-code behavior intentionally; configure templates/deep links, use the matching resend operation, handle duplicate/expired codes and throttling, and test the real signup confirmation flow. Do not create a second passwordless customer account accidentally while attempting provider confirmation.

## Further correctness/usability work

- **Earnings time semantics:** `earnings_service.dart:31–44` summarizes by booking date, uses a Monday boundary retaining the current time of day, and does not bound future entries. Define earned/settled dates, MYT calendar boundaries and payout status meanings. The schema's `Pending/Processing/Completed` payout labels do match this code; no status-name mismatch is claimed.
- **Service validation:** `edit_service_screen.dart:43–58` silently turns invalid prices into `0` and invalid duration into `60`, and can submit a null category. Validate required fields and exact monetary input explicitly. The service field names and `Fixed/Hourly` pricing labels match the audited schema.
- **Identity lookup consistency:** the Auth-ID/application-ID assumption appears in `profile_service.dart:15`, `service_service.dart:11`, `:44`, `booking_service.dart:11`, `earnings_service.dart:11`, `notification_service.dart:11`, `:27`, and `ai_service.dart:11`. Centralize the resolution rather than patching each separately.
- **Theme:** `provider_theme.dart:4–5` and several auth/profile screens hardcode blue. Apply the requested orange/white theme in the mobile phase.
- **Path casing:** `lib/main.dart:3–6` imports `provider/...`, while the committed folder is `lib/Provider`. Normalize paths/casing for portable builds; Windows filesystem behavior should not be relied upon by Linux CI.
- **Failure behavior:** some service methods silently return when the provider/session ID is missing, and profile screens lack uniform load/save error handling. The user must not receive apparent success when no write was performed.

## Recommended implementation order after the admin phase

1. Define/test the authenticated customer/provider identity and profile API, role gates and confirmation flow.
2. Integrate profile fields, private credential submission, working hours and service CRUD against least-privilege contracts; align admin review behavior and weekday conventions.
3. Agree the booking/payment/completion policy, then implement actor-specific transactional booking APIs and contact projections.
4. Implement chat and notifications as separate data and delivery paths.
5. Reconcile earnings/payout definitions, then implement the chosen matching/scheduling product with measurable evaluation.
6. Run Flutter analysis/tests on the user's Flutter 3.38.8 / Dart 3.10.7 setup and exercise real flows at Pixel 3a dimensions, including keyboard, loading, denied access and retry cases.

The mobile permission failures described above identify APIs still to build. They do not justify weakening the administrative database protection. The newly received provider code has been preserved for the next phase.
