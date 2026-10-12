# Customer gallery, payment methods, coverage and reviews

## Customer and provider flows

- Open a chat photo, then swipe horizontally or use the previous/next arrows. Pinch to zoom; zoom out before swiping between photos. Earlier conversation photos load on demand. Private Storage authorization is unchanged; the viewer keeps only nearby download futures.
- At Payment, select **FPX online banking** or **Debit / credit card or GrabPay** before opening checkout. Stripe hosts and validates card details; the app never accepts or stores card numbers or CVC. An existing checkout retains its original method group until it expires, preventing parallel charges for one booking. Touch ’n Go / DuitNow QR is deferred.
- Providers: open **Service Areas**, set a radius, choose a public service-area centre on the map, then save the profile. Removing the public pin hides the coverage. Existing profiles remain valid without a published pin.
- Customers: open **Add Service Location → Show service areas**. Published verified providers appear with labels and radius overlays. Tap a marker to see services and whether the selected address lies inside its radius. Coverage is provider-declared and does not guarantee appointment availability. The API returns up to 50 nearby eligible providers.
- Open **Profile → My reviews → Ready to review**, or an eligible booking. Reviews require a successful payment and a provider-completed service. Paying a Confirmed booking alone does not unlock a review. Existing reviews remain visible below the queue.

## Payment integrity

All checkout remains in the selected Local Life Stripe sandbox. Live keys and live webhook events are rejected. Prices, ownership, deadlines, availability, retries and receipt eligibility remain server-controlled. Webhooks retrieve the successful PaymentIntent and verify the actual payment method, amount and currency before recording a receipt. Duplicate events cannot relabel an existing payment.

The sandbox's default payment configuration enables cards and GrabPay but does not expose FPX as available. The previously working explicit FPX Checkout path and API version are therefore preserved. The new card/GrabPay path uses dynamic Checkout methods, excludes FPX and Alipay, hides Link and disables adaptive pricing to retain the quoted MYR amount. Card lengths follow Stripe's card-brand validation rather than a hardcoded 16-digit rule.

References: [Stripe dynamic payment methods](https://docs.stripe.com/payments/payment-methods/dynamic-payment-methods), [GrabPay](https://docs.stripe.com/payments/grabpay), [FPX](https://docs.stripe.com/payments/fpx).

## Supabase deployment and migration history

Deployed to project `znxhiymvmluxmdaxzxkt` on 12 October 2026:

- `20261012093557_customer_coverage_review_queue.sql`
- `20261012093600_checkout_payment_methods.sql`
- `customer-checkout` version 12 (JWT verification enabled)
- `fpx-webhook` version 11 (Stripe signature verification)

The migration filenames match the versions recorded in Supabase. Do not reapply the migrations or rename them to their earlier local draft timestamps. Existing secrets and the Stripe webhook endpoint were retained.

## Validation and limits

- Flutter suite: 89 tests passed; 18 gallery/payment/photo tests rerun after the final gallery cache and review refresh guards.
- Gateway tests: 26 passed, including invalid client input, verified payment methods, amount checks and webhook failures.
- SQL regression gate: 299 assertions passed against the deployed schema in a rolled-back transaction, covering existing admin/customer flows and new permissions, review eligibility, coverage filtering and payment-method recording.
- Screen captures checked for payment choices, review entry and coverage empty state.
- An unpaid Stripe sandbox Checkout session showed Card and GrabPay. No real money or new test payment was submitted during this change.

Physical-device pinch/swipe, provider GPS permissions and end-to-end card/GrabPay return-to-app behavior still need acceptance testing. Providers must publish actual service-area centres before real coverage can appear; no locations were inferred from private addresses or invented for existing accounts. Existing database security advisories were not changed by this feature work.
