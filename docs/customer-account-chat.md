# Customer account and provider chat

This change builds on provider commits through `40cba27`. The provider screens remain in place; shared identity lookups, notification routing and chat storage are connected to the customer workflows.

## Customer changes

- Bottom navigation: Explore, Bookings, Notifications, Profile. The Explore header opens Chats.
- Registration and profile phone editing display a fixed `+60`. Enter the Malaysian mobile number without its initial `0`, for example `102049818`. Stored value: `+60102049818`. Existing formatted numbers are converted to national format when opening the editor. Login continues to use email and password.
- Forgot password: enter email, new password and confirmation; request an email code; enter the latest code; verify; update the password; return to sign-in. The password remains only in screen memory until verification and is cleared on completion/disposal.
- Profile: tap the photo/name to edit, then Save. Name, phone, photo, service preferences, optional bio, gender and birthday are saved together. Email is displayed as the verified sign-in address, not an unverified editable profile field.
- Settings: account/security, addresses, chat, booking help, privacy explanation and logout. Account/security includes email-code password change and sign out all devices.
- Feedback: customer snackbars are removed. Success/error feedback uses acknowledged OK dialogs. Confirmations describe the action before Cancel/OK. Inline retry controls remain available after an error. Simultaneous background errors do not stack dialogs over another route.

## Chat behavior

Customers can search verified active providers by business name, open chat from provider or booking details, and continue past conversations from the inbox. Providers have a Chats button in their profile header, chat notification links, and their existing booking chat screen connected to the same messages. Its toolbar opens the full paginated conversation view.

Messages are persisted in `chat_messages`; a customer/provider pair has one `chat_conversations` record. `chat_members` holds each person's pin, visibility, block and read state. Notification records contain a link and generic notification text, not the conversation history.

- Swipe a conversation left for Pin/Unpin and Delete. The overflow menu offers the same actions for accessibility.
- Delete clears only the current person's visible history and inbox. It does not erase the other participant's copy. A new incoming message reopens the inbox item without restoring cleared history. The server returns the deletion boundary so another device can clear its cache too.
- Block/unblock is available inside a conversation. The blocked-chats button in the inbox also lists deleted blocked conversations, so either role can reach its own unblock control.
- Realtime updates, app-resume refresh, a 20-second foreground fallback, and manual refresh reconcile authoritative state. Older messages and inbox pages load on demand.
- A retried send keeps its request UUID until it succeeds or the message changes. The server rejects reuse with a different payload. A sender is limited to 30 messages/minute and a customer to 10 newly created conversations/minute. Existing conversations remain reachable.
- Chat does not reserve a slot, approve a booking, change the price or confirm payment. Customers must submit the booking; provider acceptance is required before payment.

## Auth and database

The recovery service uses an isolated Supabase client with no persisted session. It calls `resetPasswordForEmail`, then `verifyOTP(type: recovery)`, checks the canonical database role is customer, and only then calls `updateUser(password: ...)`. A provider/admin identity cannot proceed through this customer's update path. Supabase Auth remains responsible for code validity, expiry and email delivery. A failed password update can retry with the verified in-memory session without consuming the OTP again.

The project's saved **Reset password** email template now contains `{{ .Token }}`. The exact source is [recovery.html](../supabase/templates/recovery.html). The existing `{{ .ConfirmationURL }}` remains for the PHP admin recovery flow. Template changes live in Auth configuration; SQL migrations do not install the email template on a different Supabase project.

Applied migrations:

1. `20261003095942_customer_accounts_chat.sql`
2. `20261003101601_chat_history_visibility.sql`
3. `20261003102736_chat_blocked_inbox.sql`

Each was applied with fail-fast regression fixtures inside a savepoint, followed by rollback of the fixtures. The migration records may include the test gate, but synthetic accounts/messages/bookings were not retained.

Chat mutations use authenticated, guarded RPCs; direct client inserts/updates/deletes are denied. Row-level security restricts conversation and message reads to participants. Identity comes from `users.auth_user_id = auth.uid()`; an Auth ID must not be assumed to equal the application's `user_id`.

The audit found live grant/policy drift. The migration restores scoped `users`/`provider_profiles` column grants and the active-account restriction on services. Provider service creation is preserved with the canonical application identity. Provider profile queries now select allowed columns explicitly. **Do not restore broad `GRANT ALL`, `SELECT *` access to users/provider profiles, or policies comparing an application user ID directly to `auth.uid()` to fix a screen.** Role, activation and provider verification remain controlled server operations.

## Added beyond the requested layout

Optional bio/gender/birthday, unsaved-profile confirmation, chat blocking and a blocked-chat list, unread counts, message retry protection, abuse limits, recovery resend cooldown, and sign out all devices are included. All-device sign-out ends refresh sessions; already-issued access tokens may remain usable until their expiry. No unsupported wallet, credit, biometric, social-login or device-management controls are displayed.

## Verification and device acceptance

Automated checks cover invalid recovery codes, wrong account role, recovery retry ordering, normalized phone values, edit/save behavior, Pixel 3a layouts, modal acknowledgement, chat send retries, provider search and pin/delete actions. Database regressions cover participant isolation, direct-write denial, retries, sender direction, unread state, per-person deletion/pinning, blocking, profile validation, and the existing admin/booking/payment behavior.

Run:

```powershell
flutter pub get
flutter test --no-pub
flutter build apk --debug --no-pub
```

Verified with Flutter 3.38.8 / Dart 3.10.7: 37 Flutter tests passed and the Android debug APK built successfully. `pubspec.lock` was resolved with this SDK; the incoming provider lockfile required Dart 3.11, so its six SDK-bound dependency versions were adjusted by `flutter pub get`.

Pixel 3a widget renders with synthetic account data: [Profile](screenshots/customer-profile.png), [Edit profile](screenshots/customer-edit-profile.png), [Recovery code](screenshots/customer-password-code.png).

The live audit confirmed chat RLS, denial of anonymous chat RPC execution and direct client message writes, inaccessible legacy password hashes, and no retained synthetic chat fixtures. Supabase's existing private-table/no-policy and admin preflight function notices remain intentional. [Leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains disabled in the project's Auth settings; this change does not claim to enable breach-password screening.

For a manual acceptance pass using your own customer and provider accounts:

1. Register using the national phone digits and confirm that +60 remains visible.
2. Request password recovery from the customer login page. Verify an incorrect code fails, then use the newest code from your email and sign in using the new password.
3. Open Profile, edit details, Save and acknowledge OK. Reopen it to verify persistence; check the Settings and Account & Security pages.
4. Open Chats, search the provider's business name and send a message. On a separate provider session, open Chats and reply. Reopen both apps to check history.
5. Pin and unpin; delete on one side and verify the other side retains history. Send a new message and verify only new messages reappear for the person who deleted. Block, delete, then use Blocked chats to unblock.
6. Discuss a time, submit the booking, and verify payment remains unavailable until the provider accepts.

Automated Auth HTTP tests do not send real emails or change real account passwords. SMTP delivery and the final real-device two-account interaction should be checked with the steps above.
