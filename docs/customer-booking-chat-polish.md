# Customer booking and chat polish — 11 October 2026

Notifications and shared customer/provider chat now use rounded 16px swipe actions that fill their card height. Chat uses the same card spacing, borders and text hierarchy as notifications. Inbox overflow menus, conversation blocking menus, the blocked inbox and settings references to blocking are removed. The duplicate Explore footer search button is removed.

Book service is grouped into service summary, address, appointment and optional instructions. An empty date offers a date-picker action. Booking details groups status/next action, appointment/address, payment and support; eligible bookings have a fixed Continue to payment button above the safe area. Expired unpaid reservations show Expired in the customer list and detail, an explanation and a provider/service entry point to choose a new appointment using current availability/pricing. Existing support, receipt, review and cancellation guards remain.

## Payment diagnosis and limits

The reported booking prefix 9C7B9244 was accepted at 2026-10-05 19:27:51 UTC. Its payment deadline was 19:57:51 UTC (6 October, 3:57 a.m. Malaysia), and its appointment was 6 October, 9:30 a.m. Malaysia. The server correctly returned can_pay=false. The old screen displayed its historical Confirmed status and buried the expiry explanation. No payment period was extended and no stale slot was charged.

The server still requires provider acceptance, a future appointment, an open reservation, and no successful/refunded payment. Client deadline handling also removes the fixed payment action when its deadline passes; checkout revalidates eligibility and price on the server. Payment receipt state only comes from verified server records.

The deployed customer-checkout, fpx-webhook and payment-return functions are ACTIVE. The implementation is Stripe FPX test mode; live keys are explicitly rejected. Mocked gateway and transactional SQL checks do not prove a complete Stripe sandbox/bank interaction. Secret configuration could not be inspected through the available connector; the local CLI has no management access token. Follow [FPX setup](fpx-test-setup.md) for the project-owned test key/webhook configuration and manual gateway acceptance test.

## Database rollout

The 20261011053324_retire_chat_blocking migration was applied to the linked FYP project with all ten regression suites inside a rolled-back fixture savepoint. It clears existing block flags without modifying messages, hidden state or cleared-through boundaries, rejects future block/unblock actions, removes blocked-list RPCs, and keeps participant/active-account checks, sender rate limits and idempotency. An inert false-only column remains for older inbox projections. Older app builds must be updated to remove their obsolete blocked-chat controls.

273 SQL assertions passed; a separate read confirmed zero remaining blocks, no retained synthetic Auth users, no anonymous chat-send permission and the authenticated grant intact. The SQL admin credential fixture was updated to the certifications bucket used by the teammate's current live admin implementation.

## Validation and shared-code review

- 71 Flutter widget/contract tests passed, including 360px/393px booking layout and keyboard checks, provider/customer swipe actions, expired payment state, payment navigation, account/session recovery and address flows.
- 273 database assertions covering admin, customer ownership, provider acceptance, checkout, chat and activity counts.
- 18 FPX gateway tests and 51 PHP admin HTTP tests passed.
- Visual previews inspected with real Roboto/Material fonts; debug APK rebuilt.
- Based on master 8e39d59 (merged PR9); provider acceptance continues to call provider_booking_reply. No provider booking rules or admin application files changed. Shared chat intentionally removes blocking for both roles.

Security advisor still reports pre-existing admin_registration_check definer grants and disabled leaked-password protection. See [function grant guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Private helper tables intentionally deny direct access through RLS without policies. The previously documented certifications storage policy concern remains outside this UI/chat change; see [prior review](customer-ui-polish.md).
