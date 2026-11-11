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

## Regression checks

`supabase/tests/customer_deletion_eligibility.test.cjs` executes the production
SQL function in PGlite across expiry boundaries, terminal states, paid active
bookings, disputes, gateway attempts, pending payments and refunds. It also checks
that rejected deletion leaves identity intact, successful preparation anonymizes
records, retries are idempotent, and clients cannot call the privileged function.

`test/customer_deletion_status_test.dart` checks the customer payment badges.
The existing cooldown tests protect the successful-deletion email restriction.
