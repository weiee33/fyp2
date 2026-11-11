# Customer waiting periods

## Behaviour

- A successful customer cancellation blocks new bookings for that customer and the same `service_id` for 30 minutes. Other services remain available. Provider rejection, administrator cancellation and automatic expiry do not start this timer.
- Repeating the same cancellation does not restart the timer. Retrying an existing booking request token returns the original booking without creating another one.
- Successful customer Auth deletion prevents reuse of the same trimmed, case-insensitive email for 14 days. Choosing the provider role or changing another account's email cannot bypass it. Email aliases are separate email addresses.
- These policies apply to actions completed after the migration. Previous deletions cannot be reconstructed from anonymized records.

## Enforcement

Apply `20261111143316_customer_cooldown_limits.sql` before releasing the mobile changes. It has been applied to the connected Supabase project.

`customer_cancel_booking` and the booking INSERT trigger use the customer row lock before the provider lock. The restriction is stored in a private table and checked against server time, including when the AI creates a booking. Existing ownership, payment, refund-review and slot validation remain in place.

An Auth DELETE trigger records the email restriction in the same transaction as deletion, using the existing trusted customer-deletion marker. Preparation failures and rolled-back deletions do not start the 14-day timer. The later diagnostic finish call is not required for enforcement. Auth INSERT/email UPDATE triggers enforce the restriction even if registration bypasses the app.

The email table stores a SHA-256 fingerprint using a private random key, not the email. Clients have no access to the fingerprint, secret or deadline tables. Expired email fingerprints are removed during subsequent customer deletions; expiry checks allow registration immediately without waiting for cleanup. The public registration preflight returns no profile information and provides readable feedback before Supabase Auth signup.

The app uses the existing customer dialogs and button theme. Cancellation and deletion confirmations disclose the wait; blocked attempts show a short English, Chinese or Malay message.

## Verification

- PostgreSQL tests: `node --test supabase/tests/customer_cooldown_limits.test.cjs` with `@electric-sql/pglite@0.5.15` on `NODE_PATH`. Covers actual booking RPC logic, cancellation retries, expiry boundaries, other customers/services, direct INSERT, email normalization, role/email-change bypass, transaction rollback and privileges.
- Flutter: `flutter test --no-pub --concurrency=2`. Includes registration preflight denial before any signup request for both account choices.
- Localization: `python tool/check_localization.py`.
- Hosted rollback checks passed using temporary customer identities through the real signup trigger, booking/cancel RPCs, deletion prepare/finish RPCs and Auth table triggers. The transactions rolled back all test data. Expiry was moved to the current server time to verify both boundaries without waiting in real time.
- Security advisor review found no new warnings. The three private tables intentionally have RLS with no client policies.

## Phone checks after merging

1. Create and cancel a future booking. Check the confirmation mentions 30 minutes. Immediately try the same service with a different time or address: the request must be rejected. Another service must still be bookable.
2. Restart the app and try again within the wait. The restriction must remain. After 30 minutes from cancellation, a valid available slot must be bookable.
3. Use a dedicated disposable customer account with no active bookings, payments or disputes. Verify the deletion screen explains the 14-day wait, then delete it.
4. Register with the same email, including different letter case. Check the clear 14-day message and that no signup proceeds. Do not delete a personal account merely to test this policy.
