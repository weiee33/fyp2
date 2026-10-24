# Analytics reports and suspended customer access

## Deployment

1. Install the PHP dependencies with `composer install --working-dir=admin --no-dev --prefer-dist` (Windows: `scripts/Setup-AdminDependencies.ps1`). Deploy `admin/vendor` with the website. Set PHP `memory_limit=512M` for Unicode reports (the Windows launcher does this). Keep `assets/fonts` in its repository-relative location outside the public web root. The renderer uses these bundled, licensed fonts for English, Malay and Chinese names; it cannot fetch remote resources or execute scripts.
2. Apply `20261023095804_suspended_customer_support.sql` once using the normal migration process. It preserves active-only mutation guards, adds verified-customer viewing helpers and permits the existing support APIs for suspended customers. It does not suspend or reactivate any existing customer.
3. Deploy `customer-geocode` with its shared handler, which now explicitly requires the identity's `is_active` value.
4. Release the Flutter app. Ship the database change first: old clients keep their existing UI, while the server still blocks suspended mutations.

## Admin reports

Apply the date/category/region/provider filters before exporting. CSV and PDF links are generated from the authorized result and applied filters, not unsaved form values. Both include daily activity, collections, categories and provider performance. All reporting dates use Malaysia time. Community metrics remain global where indicated; gross collection is before refunds, not net revenue.

Chart points, category segments, metrics and provider rows open detail dialogs with exact values. Native tables remain available. Keyboard users can focus points and use Enter or Space; Escape closes the dialog and restores focus.

## Customer suspension

Only verified **customers** gain the support exception. Suspended providers and administrators retain the existing access restrictions. `account_identity` returns `is_active`; authority remains the database record, never user-editable metadata.

The app checks status after login, on resume and every 15 seconds while signed in as a customer. A red banner and border remain visible on customer routes. Normal taps and keyboard input are blocked; scrolling and the four main viewing tabs remain available. Help Centre, support photos, owned request history, admin responses and sign-out remain accessible. A failed status refresh restricts actions until access can be verified again. Reactivation restores normal access on the next successful check (or the banner's refresh button).

The database rejects new bookings, cancellations, checkout creation, profile/address edits, notification edits, chat/AI actions and unrelated uploads while suspended, even with a stale client or direct RPC request. Financial callbacks for payments already initiated continue to reconcile authoritative gateway events. Suspension is not a refund or cancellation of an already-created external payment session.

## Verification

- `admin/tests/run.php`: authorization, applied filters, valid PDF download and existing admin workflows.
- `test/customer_suspension_test.dart`: action interception, keyboard blocking, scrolling and permitted passive navigation.
- `supabase/tests/customer_suspension_regression.sql`: run after `admin_regression.sql` inside `BEGIN ... ROLLBACK`, with the migration if not installed. Tests identity, read ownership, mutation denial, support, admin responses and reactivation.
- `supabase/tests/customer_account_edge.test.mjs`: suspended geocoding is rejected before any location-provider call.

Validation uses synthetic fixtures. No production account should be suspended for testing.
