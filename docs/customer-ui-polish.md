# Customer screen polish and integration review

Based on `8783442` from master, including the teammate's provider chat/profile and admin document updates.

## Customer changes

- Explore's service-address selector uses the modal sheet's accessible grey drag handle instead of a close icon. Swipe down, tap outside or use Back to dismiss it.
- The map's address form has more space between groups, persistent field labels, larger input padding, and a multiline street/unit field. Search stays pinned; the roomier form scrolls inside the existing three-position panel.
- Profile keeps the Bookings, My reviews and Chats shortcuts without the redundant heading/View all row.
- Settings uses the same white account-card layout for `Logout Your Account`.
- Login navigates immediately on success. Logout retains its confirmation and error handling, then returns directly to the portal without another success dialog. Verification, validation and destructive-action dialogs remain.
- Login, registration and signed-out password reset clamp at their scroll limits. Signed-in Change Password still bounces, now in a full-height viewport so its short content is not clipped at the old viewport boundary during a drag.

## Teammate integration review

The incoming changes do not modify customer code, shared chat APIs, booking/payment services or checked-in database migrations. Provider chat still delegates to the existing shared conversation service; the provider profile now opens that shared inbox from its header. The old customer session-cancellation fix remains present.

The incoming lockfile included SDK-pinned packages requiring Dart 3.11. It has been regenerated with the project's specified Flutter 3.38.8 / Dart 3.10.7. This restores compatible pinned versions without upgrading Supabase or changing the teammate's provider implementation. Removed generated plugin registrants regenerate through Flutter tooling.

The admin document route now points to the live `certifications` bucket. Read-only Supabase inspection found two separate provider/admin concerns that this customer UI patch does not resolve:

1. The `certifications` bucket is public. Its four authenticated storage policies check only the bucket ID. The restrictive active-account policy prevents inactive accounts, but it does not restrict writes to providers or to the object owner. Consequently, the policy predicates permit active customer accounts and unrelated providers to mutate certification objects. This needs a coordinated provider/admin storage-hardening change, including private reads and signed-link handling; changing only the bucket visibility would break the provider's current public-URL workflow.
2. The live `private.admin_document` implementation was changed to accept `certifications` URLs, but the migration history still ends at `20261004103821`; there is no checked-in migration for that manual database change. A fresh database cannot reproduce the current document behavior from this repository alone. The PHP document route also no longer encodes object path segments, so filenames with URL-special characters need explicit end-to-end coverage in that follow-up.

These findings mean the provider/admin storage configuration is not certified as correct. No live SQL or customer account data is changed by this UI patch.

## Verification

Run `flutter test --no-pub`, the Chrome session-cancellation suite from `.github/workflows/flutter.yml`, and `flutter build apk --debug --no-pub` with Flutter 3.38.8. The added gesture tests distinguish the three clamped public forms from the full-height bouncing signed-in form. Existing address tests cover both 393×808 and 360×720 plus keyboard use.

For manual acceptance, expand/collapse the map panel, edit a long street address, dismiss the service-address selector by dragging, cancel/confirm logout, and drag Change Password while its submit button is visible. Login success should enter Explore directly. No real customer credentials are needed by automated layout tests.
