# Customer alerts and receipt delivery

## Deployment status

- Android app `com.example.fyp2` is registered in Firebase project `local-life-service-assistant`. The checked-in `google-services.json` contains public app configuration, not server credentials.
- Supabase project `znxhiymvmluxmdaxzxkt` dispatches `customer-delivery` immediately after a delivery job commits, with a minute scheduler for recovery. Push delivery is enabled.
- Resend's free email service is provisioned through Stripe Projects. Its API key is stored in Supabase Vault. **Sandbox email delivery is enabled only for the verified Resend account owner.** The shared testing sender is `Home Serve <onboarding@resend.dev>`. Other recipients require a verified sending domain.
- Payments remain in Stripe sandbox mode. Checkout uses Home Serve's orange button, rounded corners and white background. Stripe's external FPX test authorization page is owned by Stripe and cannot be restyled by this app.

## Phone alerts

The customer app requests notification permission once after sign-in. If Android permission is denied, enable notifications in the phone's app settings and reopen Home Serve. Registration runs automatically; there is no separate Phone Alerts row in Account Settings.

Tokens are bound to a Supabase auth session and customer account, with at most five devices per account. Logout removes the registration where possible, revokes the session, clears local alerts and deletes the Firebase token. The worker excludes revoked sessions, inactive customers, dismissed notifications and expired/paid booking acceptance prompts. In-app read status does not suppress important phone alerts: opening an in-app notification does not prove that Android displayed it. The worker removes permanently invalid Firebase tokens. Notification taps recheck ownership before opening Booking Details.

Booking requests, provider replies and important booking/payment events create durable delivery jobs. Routine profile changes and ordinary chat messages remain in-app notifications. Acceptance alerts expire with the payment/reservation deadline; other alerts expire after six hours. Lock-screen text excludes names, addresses and payment amounts. Foreground alerts use Android's `booking_alerts` channel; background delivery is handled by Firebase, avoiding duplicate displays.

Delivery is retried with backoff, a five-minute lease and a maximum of eight attempts. Each worker claims up to five jobs of each enabled kind. Delivery is best effort: network connectivity, Android notification settings and force-stop behavior can prevent or delay an alert. In-app notifications and the booking deadline remain authoritative.

## Receipt email activation

The verified Stripe webhook records payment and queues a receipt atomically. The recipient is the email collected by Stripe Checkout. Only validated Stripe receipt links are included; retries use a stable Resend idempotency key. Duplicate Stripe events do not create duplicate receipt jobs. Sandbox receipts explicitly state that no real money was collected.

To expand email delivery beyond the verified account owner:

1. Add an owned sending domain in Resend and publish its required DNS records.
2. Verify the domain, then set Vault secret `home_serve_receipt_from_email` to an address on that domain.
3. Confirm `home_serve_resend_api_key` is configured, clear the owner-only `home_serve_receipt_test_recipient` restriction, and keep `home_serve_delivery_email_enabled` set to `true`.
4. Complete an authorized sandbox booking/payment using a controlled recipient and verify delivery, receipt contents and duplicate-webhook behavior.

Queued receipt jobs expire after 20 hours, before the provider's idempotency window ends. Expired receipts are not backfilled automatically. Email payloads are redacted after seven days by queue maintenance. Existing receipts remain available inside the app for every customer. The test-recipient restriction rejects other recipients without forwarding their receipts to the account owner.

## Server configuration

Vault secret names (never put their values in source control, app assets or logs):

- `home_serve_firebase_service_account`: dedicated Firebase service account with the Firebase Cloud Messaging API Admin role.
- `home_serve_delivery_worker_secret`: independent 64-character hexadecimal worker authentication secret.
- `home_serve_project_url`: Supabase project URL used by the scheduler.
- `home_serve_delivery_push_enabled` / `home_serve_delivery_email_enabled`: explicit delivery switches.
- `home_serve_resend_api_key` / `home_serve_receipt_from_email`: email credentials and verified sender.
- `home_serve_receipt_test_recipient`: required account-owner restriction when using the shared `resend.dev` testing sender; remove only after configuring a verified domain sender.

The service-role-only `delivery_configuration` RPC reads an allowlist of Vault settings. Client roles cannot read the outbox, device table or delivery configuration directly. Public registration functions enforce customer/session ownership. The worker verifies its dedicated bearer secret; the Stripe webhook retains signature verification and server-side payment checks.

## Validation and device acceptance

Automated coverage includes the customer UI, notification category mapping, shared AI menu selection/actions, payment webhooks, provider failures, queue authorization, session isolation, lease ownership, deduplication and expiration. Database regression fixtures run in a transaction that is rolled back.

On a physical Android phone with Google Play services:

1. Install the updated APK, sign in as a customer and allow notifications.
2. Make a test booking, background the app, and have its provider accept it. Expect a Booking Accepted notification shortly after confirmation; tapping it should open that booking.
3. Repeat in the foreground, then with the app normally closed. Verify only one notification appears for each event. Android force-stop is not equivalent to normal closing.
4. Check logout/account switching does not expose another customer's booking. Verify dismissed, paid and expired acceptance jobs do not produce stale payment prompts.

On 17 October 2026, Firebase accepted a diagnostic message to the registered owner device and the owner confirmed that the alert appeared while Home Serve was in the background. Resend reported both queued owner sandbox receipts as delivered. Booking-event timing and tap navigation should still be checked through the acceptance flow above. This configuration covers Android; iOS/APNs and web push are not configured.
