# Analytics reports and suspended customer access

## Deployment

1. Install the PHP dependencies with `composer install --working-dir=admin --no-dev --prefer-dist` (Windows: `scripts/Setup-AdminDependencies.ps1`). Deploy `admin/vendor` with the website. Set PHP `memory_limit=512M` for Unicode reports (the Windows launcher does this). Keep `assets/fonts` in its repository-relative location outside the public web root. The renderer uses these bundled, licensed fonts for English, Malay and Chinese names; it cannot fetch remote resources or execute scripts.
2. Apply `20261023095804_suspended_customer_support.sql` once using the normal migration process. It preserves active-only mutation guards, adds verified-customer viewing helpers and permits the existing support APIs for suspended customers. It does not suspend or reactivate any existing customer.
3. Deploy `customer-geocode` with its shared handler, which now explicitly requires the identity's `is_active` value.
4. Release the Flutter app. Ship the database change first: old clients keep their existing UI, while the server still blocks suspended mutations.

## Admin reports

Apply the date/category/region/provider filters before exporting. CSV and PDF links are generated from the authorized result and applied filters, not unsaved form values. Both include daily activity, collections, categories and provider performance. All reporting dates use Malaysia time. Community metrics remain global where indicated; gross collection is before refunds, not net revenue.

Daily charts provide a crosshair and live date/value readout. Hover or drag to inspect, click to pin, and use arrow keys/Home/End to navigate; Escape releases inspection. All/7D/30D/90D, zoom buttons and the date-window slider only adjust the visible chart window, not applied report filters or CSV/PDF exports. Series toggles always retain one visible series. Category segments, metrics and provider rows still open exact-value dialogs. Native daily tables remain available, including without JavaScript.

## Customer suspension

Only verified **customers** gain the support exception. Suspended providers and administrators retain the existing access restrictions. `account_identity` returns `is_active`; authority remains the database record, never user-editable metadata.

The app checks status after login, on resume and every 15 seconds while signed in as a customer. A red banner and border remain visible on customer routes. Normal taps and keyboard input are blocked; scrolling and the four main viewing tabs remain available. Help Centre, support photos, owned request history, admin responses and sign-out remain accessible. A failed status refresh restricts actions until access can be verified again. Reactivation restores normal access on the next successful check when the app resumes or during its automatic status check.

The database rejects new bookings, cancellations, checkout creation, profile/address edits, notification edits, chat/AI actions and unrelated uploads while suspended, even with a stale client or direct RPC request. Financial callbacks for payments already initiated continue to reconcile authoritative gateway events. Suspension is not a refund or cancellation of an already-created external payment session.

## Verification

- `admin/tests/run.php`: authorization, applied filters, valid PDF download and existing admin workflows.
- `test/customer_suspension_test.dart`: action interception, keyboard blocking, scrolling and permitted passive navigation.
- `supabase/tests/customer_suspension_regression.sql`: run after `admin_regression.sql` inside `BEGIN ... ROLLBACK`, with the migration if not installed. Tests identity, read ownership, mutation denial, support, admin responses and reactivation.
- `supabase/tests/customer_account_edge.test.mjs`: suspended geocoding is rejected before any location-provider call.

Validation uses synthetic fixtures. No production account should be suspended for testing.
