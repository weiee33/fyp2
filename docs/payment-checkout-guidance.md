# Payment journey and configuration validation

The reported booking D72FAD38 was accepted by its provider but had no payment record and zero checkout attempts. The deployed checkout returned a missing environment configuration error before reserving a checkout attempt. Provider acceptance is distinct from bank authorisation and server-confirmed payment.

## Changes

- Booking details now says Provider accepted your booking, avoiding the implication that FPX already accepted a transaction.
- Payment shows three stages: provider acceptance, bank payment, payment confirmation. Opening a browser never completes the latter two stages.
- Rounded summary/error/appointment cards, a fixed payment/receipt button, Malaysia-time deadline, expired-state guidance and explicit FPX test-mode explanation.
- Inline errors preserve the actual failure message instead of replacing it with a misleading Payment failed message or an extra modal.
- Failed browser launches do not advance the journey. Successful launches trigger bounded status polling: five seconds, at most twelve checks, paused while backgrounded, restarted on return/manual check, stopped on receipt/dispose.
- Checkout returns a stable checkout_setup_required error code and checks both the Stripe test key and webhook signing secret before creating any checkout attempt. Existing session/price/idempotency/signature checks remain.

## Deployment and validation

customer-checkout version 7 was deployed with JWT verification enabled. Its downloaded source was checked for the setup code and webhook preflight. No database schema, payment records or bookings were changed. The selected Stripe sandbox now has an enabled Checkout webhook (`we_1UPJU6DAm2GCmCDsIxra6aKk`) with the four required events and API version 2025-02-24.acacia. Secret values were not installed in Supabase.

75 Flutter tests and 21 gateway tests pass. Payment screenshots were rendered with Roboto/Material fonts. Bank launch failure, missing secret, missing webhook, invalid webhook format, no premature receipt, bounded polling and stop-on-success paths are covered. Static analysis reports no issues, and the Android debug APK builds. The Stripe connector is now connected. Account acct_1UOdXqDAm2GCmCDs is a Malaysia sandbox, but its account read reports charges disabled / verification pending and its payment configuration reports FPX unavailable and off. The owner must inspect the FPX activation requirement and install the matching test API key and deployed webhook signing secret in Supabase before an end-to-end sandbox payment can be verified.

Follow [the setup guide](fpx-test-setup.md). Do not put secrets in chat or source code. No real money has been collected or verified by these tests.
