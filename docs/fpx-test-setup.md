# Stripe FPX test setup

Stripe FPX test mode was selected for FYP development. It uses simulated bank outcomes without taking real money. This does not promise free live transactions: check [Malaysia pricing](https://stripe.com/en-my/pricing). FPX uses MYR and requires a supported Malaysia account; see [Stripe FPX](https://docs.stripe.com/payments/fpx) and [testing](https://docs.stripe.com/testing).

## Configure your own account

1. Create/sign in to a Stripe Malaysia account. Enter its test environment and enable FPX in payment-method settings. Complete any account requirements Stripe displays; do not enter real banking details for sandbox tests.
2. In Supabase Dashboard → project `znxhiymvmluxmdaxzxkt` → Edge Functions → Secrets, add `STRIPE_SECRET_KEY` with your **test** secret beginning `sk_test_`. Do not put it in Flutter, PHP public files, GitHub, or chat. Supabase already supplies its server URL, anon key and service-role key to Edge Functions.
3. In Stripe's test webhook/event-destination settings, create an endpoint at:

   `https://znxhiymvmluxmdaxzxkt.supabase.co/functions/v1/fpx-webhook`

   Subscribe to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, and `checkout.session.expired`. Use API version **2025-02-24.acacia**, matching checkout requests. Copy this endpoint's signing secret into Supabase as `STRIPE_WEBHOOK_SECRET` (`whsec_...`). A Stripe CLI listener has a different signing secret; use the one for this deployed destination.
4. The three Edge Functions are already deployed. Do not disable JWT verification on `customer-checkout`; `fpx-webhook` authenticates Stripe signatures, and `payment-return` verifies its signed link.

## Acceptance test

1. Use an active customer and an active verified provider with an active service and working hours. Choose an appointment sufficiently far ahead (for example tomorrow).
2. Create the booking as customer. Confirm payment is unavailable while Pending.
3. Open the provider's Bookings page, accept the slot, then refresh the customer booking. Payment should become available.
4. Open secure payment, choose a test FPX bank, and exercise the success and failure outcomes supported by Stripe's test page. Return to the app and check payment status. A browser redirect alone is never evidence of payment.
5. For success, verify a single stored payment, the matching amount/reference in the receipt, and both parties' notifications. Resend the same Stripe event: there must still be one payment. Failed or abandoned attempts must not create a receipt.
6. Confirm service start is refused without payment or more than one hour before the appointment. Complete a paid service when eligible; submit one customer review and verify the provider aggregate. A second review must fail.
7. Cancel a paid upcoming booking and inspect its administrator refund-review dispute. No automated refund or provider payout is implemented by this test checkout.

Missing credentials produce a controlled configuration error. Live `sk_live_` keys and live callbacks are rejected. Tests written in this repository use mocks/synthetic database records; a real Stripe sandbox checkout remains to be exercised after configuration.

Stripe Checkout is hosted externally and the app refreshes on return. [Checkout API](https://docs.stripe.com/api/checkout/sessions/create) and [webhook signature verification](https://docs.stripe.com/webhooks/signature) describe the external contracts.
