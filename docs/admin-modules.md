# FYP 2 administrative website: scope and implementation map

Updated: 1 October 2026. This document describes the PHP administrative website implemented in this repository. It distinguishes working website/database operations from external delivery integrations and future mobile work. It is not a claim that the entire 23-module FYP application is complete.

The website uses the shared Supabase database and Supabase Auth. Customers and providers will use the Flutter mobile application; they do not receive administrative access by selecting a role at sign-in. The interface uses orange and white as requested. The PHP website runs in a browser independently of the Android emulator, even when its source is edited in Android Studio.

## Source reports

Page references are **PDF viewer page numbers, counted from the cover**. The reports are in the parent workspace folder:

- `FYP_Project1_AngWeiEe.pdf` (“Ang”), especially Chapter 4 pp. 58–162.
- `Fyp 1 - Lam Yi MIng.pdf` (“Lam”), especially Chapter 4 pp. 52–161.
- `../FYP2_Design_Review.md` records the earlier review and cross-report conflicts. Its recommendations were analysis; the implementation choices below describe the current code, not approval of all future mobile business rules.

## Report-to-implementation mapping

| Owner and report module | Chapter 4 reference | Implemented website behavior | Boundary or remaining work |
|---|---|---|---|
| Ang: Admin authentication | Use case pp. 69–71; login/OTP mockups pp. 147–148 | Admin-only email/password login, invited-account activation, email confirmation, authenticator enrollment and six-digit TOTP verification, logout, password recovery and reset | Supabase sends account confirmation/recovery email. Authenticator TOTP replaces the unspecified/email OTP mechanism. Production email delivery depends on Supabase Auth configuration. |
| Ang: User management | Use case pp. 72–73 | Search/paginate user registry, view account information and action history, suspend/reactivate customer or provider access with a reason | Administrator accounts cannot be suspended through this screen. User lifecycle screens in the mobile app are separate work. |
| Ang: Service provider management and verification | Use case pp. 74–76 | Search verification queue; review business profile, licence information, certifications, expiry, working hours and portfolio; verify credentials; approve, reject or return provider to pending; preserve rejection reason | `Verified` is the stored approval label. Document access uses the private `provider-documents` bucket and a short-lived signed link. No automatic government/issuer identity verification is claimed. Provider status email is queued, not delivered by this website. |
| Lam: Service category management | Activity p. 55; use-case diagram p. 77; category mockups pp. 133–135 | Create/edit categories and subcategories, descriptions, colour, display order, active status and icon upload; filter/search/paginate; delete unused categories | Categories with services or children cannot be deleted. Deactivation preserves history. This deliberately corrects the mockup's destructive cascade-deletion behavior. |
| Lam: Booking and order monitoring | Activity p. 57; use-case diagram p. 77; booking mockups pp. 135–136 | View/filter/search bookings, inspect customer/provider/service/address/payment and status history, apply permitted administrative status transitions, cancel with a reason, open disputes, request refunds, export filtered bookings as CSV or a printable PDF report | Administrative confirmation requires a successful recorded payment. No payment is initiated or refunded by changing booking status. PDF creation uses the browser's Save as PDF option. The final customer/provider booking policy remains separate work. |
| Lam: Analytics and reporting | Activity p. 59; use-case diagram p. 77; analytics mockup p. 136 | Date/category/region/provider filters; metrics from actual database records; daily bookings/new-profile activity and gross collection charts; service popularity donut and exact category table; provider completed-booking performance; visible review average; recorded platform fees; pending refund total; CSV report export | Service-category filters include descendants. Member-registration counts and the pending-provider verification queue remain community-wide; other booking/payment/provider measures use the selected service scope. Monetary labels distinguish gross collected from net revenue. |
| Ang: Administrator portion of the customer review module | Moderation alternative flow pp. 91–92 | Review visible/flagged/hidden feedback, inspect linked booking, hide or restore a review with a reason, retain moderation audit | Customer review submission and image upload remain mobile work. Low ratings alone are not grounds to hide feedback. |

The six primary administrative modules are shared within one website rather than implemented as separate administrative systems for each teammate. Review moderation is an administrative responsibility inside Ang's wider customer review module, not a replacement for that whole module.

## Administrative permissions

Both roles must have an active admin profile, a linked Supabase Auth identity, a confirmed email and a verified MFA session. The database enforces these prerequisites independently of the navigation interface.

| Capability | Staff Admin | Super Admin |
|---|---|---|
| View overview, users, providers, categories, bookings, reviews, disputes, refund queue and analytics | Yes | Yes |
| Suspend/reactivate customer and provider accounts | Yes | Yes |
| Review credentials and decide provider verification | Yes | Yes |
| Create/edit/deactivate categories; delete categories that are unused | Yes | Yes |
| Apply permitted booking status changes with a reason | Yes | Yes |
| Moderate reviews and open/review/resolve disputes | Yes | Yes |
| Export available booking and analytics CSV reports | Yes | Yes |
| Print filtered booking report / save as PDF through the browser | Yes | Yes |
| Record a refund request against a successful payment | No | Yes |
| Read the global audit trail | No | Yes |
| Assign administrator roles, invite staff or suspend another administrator through the UI | No | No; no role-management screen is implemented |

The initial reserved Super Admin email is `weiee0303@gmail.com`, as specified by the user. An invitation reserves authority; it is not itself a Supabase Auth account or password. The owner activates the account and chooses the password privately. Additional administrator provisioning is an explicit backend/invitation process; ordinary sign-up must not assign admin authority.

## Website operations that are ready

Given the migration and runtime configuration, the implemented pages read and mutate live Supabase records through the admin RPC contract. They include search, status filtering, pagination, validation, clear empty/error states and accessible responsive navigation. Detail forms pass CSRF protection and record versions. A changed record rejects an outdated update rather than silently overwriting the other administrator's decision.

Important current rules:

- Booking transitions are `Pending → Confirmed/Cancelled`, `Confirmed → In-Progress/Cancelled`, and `In-Progress → Completed/Cancelled`. Closed bookings cannot be reopened through this interface. This is the administrative transition contract; it does not settle every cross-report customer/provider acceptance and settlement question.
- `Confirmed` requires a recorded successful payment. Completion changes the booking record; it does not prove customer acceptance, release real escrow funds or execute a provider payout.
- Working hours use Monday as `day_of_week = 0` through Sunday as `6`, matching the existing provider writer.
- Provider verification and account access are distinct. Suspending a user account does not rename the provider's credential verification status.
- Provider approval requires licence information or a verified, current credential. The administrator must assess the supplied evidence; the database gate is not an authenticity certification.
- One open dispute is allowed per booking. Resolution records the decision and responsible administrator. Resolving a dispute does not automatically cancel a booking or refund money.
- Refund requests are capped by the remaining successful payment amount, use exact decimal amounts, and are restricted to Super Admin. Concurrent/outdated submissions are guarded by the database transaction and version check.
- Category hierarchy edits reject cycles and duplicate sibling names. Deleting an in-use category is rejected.
- Saved administrative actions record audit information and reasons. The website does not expose the legacy password-hash column.

## External operations that are queued or not connected

These boundaries must stay visible in demonstrations and the final report:

| Operation | Implemented now | Required next integration |
|---|---|---|
| Provider verification/account/booking status notifications | A notification row is stored and an email outbox item is queued for the relevant event | A retryable email worker, email provider/configuration and delivery monitoring. The website does not send these transactional emails itself. |
| Account activation and password recovery emails | Calls Supabase Auth's confirmation/recovery flows | Correct Site URL/redirect allowlist and an operational Supabase Auth email configuration. This is separate from the transaction outbox. |
| Refund processing | Validated `Requested` record and a read-only refund queue; explicit message that funds have not moved | Selected gateway's refund API, idempotent processor, callback verification/reconciliation and final gateway result. No gateway worker is included. |
| Customer/provider push notifications | Database notification information is available | FCM token registration, delivery service and Flutter receiving/deep-link screens. |
| Escrow release, provider earnings settlement and payouts | Existing payment/earnings information can be displayed | An agreed completion/dispute/settlement policy and gateway-supported implementation. Existing escrow fields alone do not establish a real funds-holding arrangement. |

No fake payment success, email delivery or provider payout is generated to make these integrations appear complete.

## Reporting workflow

On **Bookings & orders**, apply search/status filters first. **Export CSV** downloads the filtered rows. **Print / Save PDF** opens a standalone report for all matching rows, not only the visible pagination page. Click the report's print button and select **Save as PDF** in the browser print dialog. An A4 landscape layout, repeated table headings and report date/filter information are prepared. PDF saving is performed by the browser; the PHP server does not claim to have created or stored a PDF file.

On **Analytics & reports**, choose the date range, service category, provider region and/or provider, then apply the filters. The category filter covers that category and its descendants. Export preserves those selections. Charts include exact data tables so displayed figures can be checked without relying on the visual scale. Service popularity counts bookings created during the period, whereas the collection chart uses successful payment receipt dates; they measure different events. Collections from bookings created before the reporting period can therefore appear without new bookings that day. Gross collections include payments subsequently marked refunded and must not be labelled net revenue.

Registrations and pending provider applications are global. Active-booking and unresolved-dispute/review counts follow the selected service scope across all dates. Category and region classification uses the current service catalogue and provider profile rather than an unimplemented historical snapshot. These definitions are also returned by the analytics RPC and displayed above the charts.

Exports are bounded to at most 10,000 matching bookings; narrow filters if the selection exceeds that limit.

## Features added or strengthened during FYP 2

These additions should be mentioned to the supervisor/user when documenting the change from FYP 1:

1. **Invited-account activation and authenticator setup:** a concrete account bootstrap path and TOTP MFA. The report's OTP intent is retained, but the delivery mechanism is clarified.
2. **Audit trail and mandatory reasons:** administrative decisions are traceable, including account actions, verification, moderation, booking changes, disputes and refund requests.
3. **Record version checks:** outdated forms cannot silently overwrite a newer change.
4. **Structured disputes and refund request records:** service issues and intended refunds have explicit statuses and ownership instead of an untracked dashboard action.
5. **Notification outbox:** transaction records can be committed with queued delivery work. External delivery still requires a worker.
6. **History-preserving category management:** hierarchy validation and safe deletion replace destructive cascade behavior in the mockup.
7. **Private credential access:** short-lived document links limit casual exposure of provider documents.
8. **Operational safeguards:** CSRF validation, escaped output, secure session handling, request validation, login throttling, and server/database permission checks. These mechanisms require continued testing; they are not a claim that no security defects can exist.
9. **Explicit report definitions:** date-range/time-zone handling and separation of gross payments, platform fees and pending refunds. CSV exports are protected against spreadsheet formula interpretation.

Search, pagination, responsive layout and empty/error states make the supplied mockups operational; they do not introduce new marketplace business modules.

## Future mobile and shared-system work

The following wider FYP modules are outside this administrative implementation: Flutter customer/provider authentication and profiles; address management; provider service creation; discovery/search; customer booking and payment initiation; provider acceptance/start/completion; chat; review submission; mobile notifications; earnings and payouts; customer recommendations/NLP chatbot; provider matching and smart scheduling.

The shared schema audit and admin foundation do not establish that all those modules are implementation-ready. Before their implementation, resolve the recorded Chapter 4 conflicts: provider acceptance versus payment confirmation, customer acceptance of completion, exact refund/settlement policy, job matching versus category suggestions, scheduling fixed appointments versus flexible windows, and single-worker versus multi-worker provider capacity.

External transactional email/refund delivery and the mobile workflows remain future integration work. They should not be silently treated as finished because the surrounding administrative screen exists.

## Code and validation references

- Entry/routes: `admin/public/index.php`.
- Authentication/configuration/security/API integration: `admin/src/`.
- Views and styling: `admin/views/` and `admin/public/assets/`.
- Database foundation: `supabase/migrations/20261001025040_admin_foundation.sql`.
- Policy indexes: `supabase/migrations/20261001031048_admin_policy_indexes.sql`.
- Filtered analytics and chart data: `supabase/migrations/20261001031124_admin_analytics_filters.sql`.
- Database regression script: `supabase/tests/admin_regression.sql`.
- Isolated PHP/HTTP integration tests: `admin/tests/`; execution details are in `admin/tests/README.md`.
- Audit/preflight evidence: `docs/database-audit/`.

Tests using a local Supabase stub demonstrate application behavior and rendering in the tested cases. They do not substitute for live Auth email confirmation, real gateway callbacks, device push delivery or end-to-end mobile acceptance testing.
