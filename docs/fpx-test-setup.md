# Stripe FPX test setup

Stripe FPX test mode was selected for FYP development. It uses simulated bank outcomes without taking real money. This does not promise free live transactions: check [Malaysia pricing](https://stripe.com/en-my/pricing). FPX uses MYR and requires a supported Malaysia account; see [Stripe FPX](https://docs.stripe.com/payments/fpx) and [testing](https://docs.stripe.com/testing).

## What the two screenshots mean

"Provider accepted your booking" means the appointment was accepted. It does not mean FPX accepted or collected money. The reported booking had zero checkout attempts and no payment record. "Checkout is not configured" is a server environment setup problem, before the bank page opens.

## Selected sandbox and remaining manual setup

The user selected **Local Life Service Assistant sandbox**, account `acct_1UOdXqDAm2GCmCDs` (`livemode: false`, country `MY`). Keep this environment selected for every Stripe step below. The connected tools created and re-read the enabled webhook `we_1UPJU6DAm2GCmCDsIxra6aKk`, named **Local Life FPX sandbox payment confirmation**. Do not create another endpoint.

The account check on 11 October 2026 returned `charges_enabled: false`, `details_submitted: false`, and `requirements.disabled_reason: requirements.pending_verification`. The default payment configuration `pmc_1UOdYSDAm2GCmCDsfvgBrMqS` reported FPX unavailable with its display preference off. The connector exposes reads for payment-method configurations but no activation write operation. The Supabase connector does not expose secret installation. These steps therefore need the account owner in the dashboards:

1. Open [Stripe payment methods](https://dashboard.stripe.com/settings/payment_methods), select **Local Life Service Assistant sandbox**, find **FPX**, and open its details. Enable it if available. If Stripe shows an activation or verification requirement, report the exact message so the next step can match it. Keep the setup in the sandbox; do not switch to live payments or invent business details.
2. In that same sandbox, open [API keys](https://dashboard.stripe.com/apikeys). Copy the **secret test key** beginning `sk_test_` (not the publishable `pk_test_` key). In [this project's Supabase Edge Function Secrets](https://supabase.com/dashboard/project/znxhiymvmluxmdaxzxkt/functions/secrets), add **STRIPE_SECRET_KEY** and paste the test secret as its value. Keep the secret out of chat, source code and screenshots.
3. Open [Stripe webhooks/event destinations](https://dashboard.stripe.com/webhooks) in the same sandbox. Select **Local Life FPX sandbox payment confirmation** (`we_1UPJU6DAm2GCmCDsIxra6aKk`), reveal its **Signing secret**, and copy the `whsec_` value. Save it as **STRIPE_WEBHOOK_SECRET** on the same Supabase Secrets page. Use this deployed endpoint's signing secret, not a Stripe CLI listener secret.
4. Save both entries and report that they are saved, without sending their values. The updated checkout checks both entries before creating a checkout attempt. Supabase already supplies its server URL, anon key and service-role key; do not replace the built-in SUPABASE variables.
5. The Edge Functions are deployed. Leave JWT verification enabled on `customer-checkout`; `fpx-webhook` authenticates Stripe signatures, and `payment-return` verifies its signed link. Once FPX is enabled and both secrets are saved, run the acceptance test below using a newly accepted future booking.

The configured webhook URL is:

`https://znxhiymvmluxmdaxzxkt.supabase.co/functions/v1/fpx-webhook`

It receives events for this account only, uses API version **2025-02-24.acacia** (matching checkout requests), and subscribes to:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`

The connector connection does not automatically transfer API keys or webhook secrets into Supabase. Creating the webhook alone does not confirm a working end-to-end payment.

Current references: [Stripe API keys](https://docs.stripe.com/keys), [FPX account and currency support](https://docs.stripe.com/payments/fpx), [webhook configuration](https://docs.stripe.com/webhooks), [Supabase secret storage](https://supabase.com/docs/guides/functions/secrets).

## Acceptance test

1. Use an active customer and an active verified provider with an active service and working hours. Choose an appointment sufficiently far ahead (for example tomorrow).
2. Create the booking as customer. Confirm payment is unavailable while Pending.
3. Open the provider's Bookings page, accept the slot, then refresh the customer booking. Open payment within 30 minutes of acceptance. An older reservation may expire while account setup is being completed; create a new future booking for this test.
4. Open secure payment, choose a test FPX bank, and exercise the success and failure outcomes supported by Stripe's test page. Return to the app. It checks status every five seconds for up to one minute; you can also select Check payment status. A browser redirect alone is never evidence of payment.
5. For success, verify a single stored payment, the matching amount/reference in the receipt, and both parties' notifications. Resend the same Stripe event: there must still be one payment. Failed or abandoned attempts must not create a receipt.
6. Confirm service start is refused without payment or more than one hour before the appointment. Complete a paid service when eligible; submit one customer review and verify the provider aggregate. A second review must fail.
7. Cancel a paid upcoming booking and inspect its administrator refund-review dispute. No automated refund or provider payout is implemented by this test checkout.

Missing credentials produce a controlled configuration error. Live `sk_live_` keys and live callbacks are rejected. Tests written in this repository use mocks/synthetic database records; a real Stripe sandbox checkout remains to be exercised after configuration.

Stripe Checkout is hosted externally and the app refreshes on return. [Checkout API](https://docs.stripe.com/api/checkout/sessions/create) and [webhook signature verification](https://docs.stripe.com/webhooks/signature) describe the external contracts.
