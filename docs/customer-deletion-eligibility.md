# Customer deletion eligibility

The mobile app displays unpaid Pending/Confirmed reservations as Expired when
their reservation deadline or appointment has passed. The deletion RPC must use
the same effective state instead of treating every stored Pending/Confirmed row
as active.

Deletion permits cancelled unpaid bookings, expired unpaid reservations and
completed bookings when no outstanding payment, dispute or refund exists.
It does not change historical booking or payment statuses to force eligibility.

Deletion remains blocked by:

- Active reservations, in-progress work, and paid Pending/Confirmed bookings.
  A past appointment does not prove that a paid service was completed. The
  customer can contact Help Centre for provider/admin resolution.
- Open or Under Review booking disputes.
- Creating/Open gateway attempts or a Pending payment. An elapsed local checkout
  deadline is not proof that an asynchronous bank payment failed. Existing
  verified gateway events must settle the attempt; unresolved attempts need
  support reconciliation.
- Requested or Processing refunds, including when a dispute was already closed.

Each blocker has a separate concise message with Chinese and Malay translations.
Cancelled bookings without a payment now display Not paid instead of Awaiting
payment. Paid, refunded and failed payment badges retain their actual outcomes.

The existing password verification, service-role-only RPC boundary, customer and
booking locks, anonymization, retry marker and 14-day email cooldown remain in
place. Deploy the `customer_deletion_eligibility` database migration as well as
the mobile build. No Edge Function deployment is needed.

## Booking anonymization compatibility

The follow-up `customer_deletion_booking_anonymization` migration fixes a second
conflict: app bookings have a request token, so the booking guard rejects address
changes even when the deletion service is removing personal information.

The guard now permits only the exact deletion scrub (address replaced with
`Deleted customer`, coordinates and instructions cleared), with every other
booking field unchanged. It requires both a private deletion record and an
already detached, inactive customer identity. There is no client-settable bypass
flag. Clearing or replacing an existing request token is also rejected so that
an app booking cannot be reclassified as legacy to evade its contract guard.

This scrub returns before acquiring a provider lock: deletion already holds the
booking locks, while ordinary booking writers lock the provider first. Other
booking updates retain the original contract, payment and overlap checks.

## Regression checks

`supabase/tests/customer_deletion_eligibility.test.cjs` executes the production
SQL function in PGlite across expiry boundaries, terminal states, paid active
bookings, disputes, gateway attempts, pending payments and refunds. It also checks
that rejected deletion leaves identity intact, successful preparation anonymizes
records, retries are idempotent, and clients cannot call the privileged function.

These tests now install the production booking guard and use non-null request
tokens. They reproduce the original anonymization failure before applying the
fix, then verify the successful path and reject attempts to change unrelated
booking fields. Earlier fixtures omitted the guard and missed this conflict.

`supabase/tests/customer_deletion_integration.sql` exercises the real creation,
cancellation and deletion RPCs with all hosted triggers enabled, including Auth
database deletion and the email cooldown. It requires an available verified
service and rolls back all synthetic data and notifications. It does not test
the mobile password entry or HTTP Auth/Storage APIs; the Edge handler tests cover
those boundaries. This integration check reproduced the old error and passed
after the follow-up migration was applied.

`test/customer_deletion_status_test.dart` checks the customer payment badges.
The existing cooldown tests protect the successful-deletion email restriction.
