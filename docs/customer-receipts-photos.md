# Customer payment presentation, PDF receipts and chat photos

## Payment experience

- Booking cards and details use explicit green Paid/check, red Expired/Not paid/cross and neutral Refunded states. Booking and payment statuses remain separate, including a payment received after cancellation.
- Booking progress animates state changes and checkout shows a brief verified-success animation. Reduced-motion preferences are respected.
- Checkout and accepted booking details display a countdown calculated from the server deadline. The existing server eligibility checks remain authoritative.
- FPX-only sandbox checkout is retained as requested. Stripe controls its hosted bank selection and bank simulator; no card fields or imitation banking credentials were added. A redirect or browser launch never marks payment successful.
- Booking C51D3C2B was checked read-only: RM60.00, FPX Success, checkout Paid with a cs_test_ session. No payment records were edited.

## Receipt

The redesigned receipt and PDF use the authorised customer_booking_receipt response. Export re-fetches this response before generating the PDF so a refund is reflected. The receipt contains the payment amount, original payment timestamp in Malaysia time, full booking/payment references, provider, service and appointment/address. There are no invented tax numbers, tax amounts or bank transaction identifiers. All current checkout payments are sandbox payments and the document explicitly says no real money was transferred; it is not a tax invoice.

Android/iOS use the native save dialog; desktop writes the chosen path; web initiates a PDF download. Cancellation does not announce success. Failures remain retryable. Roboto is bundled with its license to support offline PDF creation. The PDF/image dependencies are pinned for Flutter 3.38.8 / Dart 3.10.7.

## Private photo messages

The shared conversation screen has a plus button offering gallery/camera, a preview with explicit Send photo and Remove actions, upload feedback, retained retry identity, private download, tap-to-enlarge and retry-on-download-failure. Android lost-picker results are recovered; iOS camera/photo usage descriptions are included. Customer and provider use the same viewer.

chat-photos is private, limited to JPEG/PNG/WebP and 5 MB per file. Object paths bind auth identity, conversation and message request ID. The database checks active participants, uploaded object ownership/type/size, message rate limits and idempotency. Message paths are immutable. Read policies honour each member's cleared-through boundary; another customer cannot access them. Failed-send uploads are retained privately for retry, not published in chat. No public URLs or service-role keys are embedded in the app.

## Verification

The migration was first exercised in a rollback-only transaction, then deployed with eleven regression suites inside a rolled-back savepoint. This includes admin, customer booking/payment/isolation, existing chat, new photo access and retry assertions, account UX and activity checks. Synthetic rows were not retained. Security advisors report only the existing private-table notices, admin_registration_check grants and leaked-password setting; no new photo finding. References: [function exposure advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Flutter checks cover status distinctions, PDF contents and refreshed refund data, countdown expiry, picker source/cancellation, photo preview/send failure/retry, existing payment polling and narrow-screen layouts. The generated A4 PDF was rendered with Poppler and its text checked with pypdf. Physical camera permissions and native Files dialogs still need an on-device smoke test; iOS cannot be built on this Windows host.

Final local verification: 84 Flutter tests passed on Flutter 3.38.8, including refunded-checkout wording and photo picker cancellation. The Android debug APK builds successfully. Browser CI also runs the existing recovery/session suite against the web import graph.
