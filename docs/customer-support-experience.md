# Customer support and scrolling

Customer routes use `CustomerScaffold` and `CustomerScrollBehavior`: one rubber-band bounce at either scroll boundary, including short content. Android's separate stretch/glow decorator is suppressed, so effects do not stack. Reduced-motion settings use clamping instead. `CustomerRefresh` still accepts only the primary, forward vertical list at its top edge. Reversed chat, nested children and horizontal gestures do not refresh. Provider routes retain their existing scrolling and chat refresh action.

The customer chat toolbar no longer has a refresh icon. Realtime, foreground resume, polling, older-message loading and visible error retry continue to work. AI halos use the same orange/white treatment as the floating navigation action. Profile shows the avatar beside the name and masked contact information, with dividers between its three shortcuts.

## Support workflow

- Help Centre lists the signed-in customer's requests and opens a general request form. Booking Details opens the same form with the booking reference. Submitted requests open their details immediately and remain accessible in Help Centre.
- Contact Support accepts general questions, feedback and complaints without a booking. Request Booking Support shows the selected service, provider, appointment and reference; its immutable request still carries the full booking ID. Administrators use the existing related-booking link to open that booking's details. Request lists distinguish general enquiries from booking support.
- Support actions share full-width, 48-pixel minimum targets and the customer theme. Photo actions have equal widths; booking cancellation is a separate destructive outline action with explicit Keep booking / Cancel Booking confirmation. Service preferences stretch to the same card width as the other profile fields.
- A request needs a 3–150 character subject and 10–4000 character description. Up to three JPEG, PNG or WebP photos, each at most 5 MB, can be selected from the camera or library, previewed and removed before sending. The client verifies image decoding.
- Sending reserves an immutable payload and upload slots. The form preserves its request ID and locks edits once sending begins, so retrying an interrupted upload or lost final response cannot create duplicate requests or replace evidence. RPC and upload waits are bounded. Users can leave a failed submission and check Help Centre before starting another request.
- A draft permits uploads for 24 hours. At most ten new drafts per customer are accepted within a rolling 24-hour period. Only one open request is allowed per booking. General requests do not need a booking.
- Requests use the existing administrator Disputes inbox. General requests display without a booking link. Attached photos use authenticated, 60-second signed links; the storage policy requires administrator MFA. Existing resolution actions populate the response shown in customer request details. Customers pull down or reopen the request to check updates; this is a support ticket workflow, not live chat.
- Customer photo links expire after five minutes. The private `support-photos` bucket has a 5 MB object limit and image MIME allowlist. Customers cannot overwrite or delete uploaded evidence. Abandoned draft files are private and require server-side storage cleanup under the operator's retention policy; draft expiry does not itself delete files.

Privacy and About are readable customer screens with English, Chinese and Malay copy. Their content describes implemented features and data flows; it does not invent company registration, certification, response-time or legal-compliance promises.

## Deployment and validation

Apply both timestamped support migrations before installing the customer build. Deploy the PHP changes with the app release so administrators can open support attachments. The migrations were applied to the linked project with the same versions stored in this repository.

`supabase/tests/customer_support_regression.sql` runs after the fixture setup section of `admin_regression.sql`, before its `Capability boundaries` section, inside `BEGIN … ROLLBACK`. The combined check passed 33 assertions covering ownership, provider/anonymous denial, MFA, immutable attachments, missing uploads, duplicate retries, booking ownership, rate limits, expiry, admin responses and Auth deletion compatibility. No real support ticket or message is created by these tests.

The PHP HTTP suite includes general-request rendering, attachment signing, authenticated signing tokens, path/slot validation and missing photos. Flutter regression tests cover bounce/refresh separation, reduced motion, retries after a lost response, photo validation/preview/removal, resume refresh without a toolbar icon, narrow translated layouts and floating-navigation clearance.

Supabase security advisors reported no new warning-level issue from these changes. The new private draft table intentionally has RLS with no client policies or table grants; guarded private functions own access ([RLS advisory explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)). Existing warnings remain for the public administrator-registration check ([function execution advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)) and disabled [leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
