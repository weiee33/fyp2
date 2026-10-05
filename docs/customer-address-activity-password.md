# Customer address feedback, activity badges and password validation

This change builds on merged PR #6 (`8e5366b`).

Follow-up: [password cancellation and address sheet](customer-session-address-sheet.md) replaces the temporary Auth client and fixed-footer layout described below after a browser session-sharing defect was found.

## Address fixes

The reported default/delete failure came from `setState(() => _addresses = future)`: the assignment returned a Future, which Flutter rejects as a state callback. The database mutation had already succeeded. A synchronous block now assigns the Future, and a regression test exercises both default selection and deletion through the real screen. Failed mutations retain the address and show the actual error. Existing atomic ownership/default-selection SQL is preserved.

The address panel opens tall enough for the fields on the target phone. My location is beside Address Details. Save and the required OpenStreetMap credit occupy a fixed footer. The panel still drags; its movement does not move the map camera. Smaller viewports, keyboards and enlarged text retain scrolling rather than clipping controls. Layout tests use the Flutter SDK's real font metrics at 393×808 and 360×720, checking every field, the default switch, Save and attribution without a drag. Physical GPS accuracy remains device-dependent.

## Activity and unread counts

- Notification cards retain swipe-left Pin/Delete and the pinned-state icon, with no overflow menu.
- Successful address additions, edits, default changes and deletions create System notifications in the same database transaction. Personal information, profile preferences and password changes are also recorded. Failed writes do not create change notifications, and unchanged profile writes are ignored. A save that changes both personal details and preferences can produce one notification for each category. No historical events are fabricated.
- Booking badges count unread notifications linked to bookings, including payment updates. Opening the booking detail marks its updates read only while the detail screen is current.
- Notification badges count unread, non-dismissed notifications. Reading or deleting a notification reduces this count.
- Chat badges count incoming unread messages across visible, unblocked conversations. Opening and reading a conversation reduces the chat count; notification items remain independently readable in Notifications.
- Red numeric badges appear on the customer navigation/profile shortcuts and Chats inbox buttons. My bookings now has a Chats button. Counts above 99 display `99+`.
- The badge widgets share one controller and subscriptions to customer notifications and chat membership. Changes/reconnect/app resume trigger an authoritative count query; a 20-second foreground fallback handles a missed Realtime event. Counts clear when the customer view is disposed. No count is inferred from a paginated inbox.

## Password flows

**Account & Security → Change Password** requires current password, a different new password of 12–128 characters, and matching confirmation. Current-password validation signs in an isolated, non-persisted Auth client and checks the canonical customer role before requesting the recovery OTP. It closes this temporary session. The OTP then proves email ownership before the normal Supabase password update. The customer's main session is not replaced by this check.

**Login → Forgot password** does not require the forgotten password. The deployed `customer-recovery` Edge function validates the email against an active, verified customer Auth identity before asking Supabase to send its configured recovery email. Unregistered, deleted, inactive and provider-only emails are rejected before sending. It never creates an account. OTP verification, role validation and password update still run in the isolated recovery session, and a failed update can reuse the verified recovery session for retry.

The requested explicit unknown-account error reveals whether an email is eligible for customer recovery. The lookup itself is service-only; clients cannot list Auth users or call the lookup SQL. The endpoint limits requests to five per email and thirty per source IP per hour, in addition to Supabase's email limits. IPs are hashed with a server secret, and no passwords or OTPs are logged. The server uses the gateway-forwarded source address. These limits supplement rather than replace gateway-level abuse protection.

## Deployment and verification

Already applied to the FYP Supabase project:

- Migration `20261004103821_customer_activity_recovery_validation.sql`.
- `customer-recovery` Edge function, with gateway JWT verification enabled (the signed anon API key supports the pre-login request).

Validation:

- 57 Flutter tests, including successful address mutations without false failure, failure preservation, layout visibility, badge changes, current-password checks, mismatch rejection and unknown-email rejection.
- 17 customer Edge tests, including eligibility rejection, request limits, no email sent for unknown accounts, and honest email-delivery errors.
- Ten SQL suites / 273 assertions, run with rollback-only fixtures, covering existing admin/customer/FPX/chat behavior, activity records, ownership, default replacement, count/read transitions and private recovery lookup permissions.
- Temporary-account live HTTP checks: default selection 200; deletion 204; System notifications counted; incorrect current password 400; unregistered recovery 404; password update/new login 200; password System notification created. The temporary Auth account and its application fixture records were removed afterward. No real customer's password was changed and no test recovery email was sent to a real address.
- Android debug APK build succeeds. Focused analysis has no errors or warnings; informational style/deprecation notices remain.

Existing Supabase notices remain for the intentional admin invitation preflight and [disabled leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). The new private throttle table intentionally has no client RLS policy or grants; [RLS notice explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Before device acceptance, fully restart the updated app. Confirm the address panel with the device keyboard, read/pin/delete notifications, and exchange messages between customer/provider devices to check Realtime delivery. Real mailbox OTP delivery and physical location permissions require that device/mailbox check; automated tests do not claim to validate Gmail delivery.
