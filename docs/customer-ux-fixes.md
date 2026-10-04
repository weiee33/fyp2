# Customer location, notifications and account fixes

Built on merged PR #5 (`8086e32`). Provider business screens and AI logic are unchanged. Shared conversation screens receive the same gesture refresh improvement.

## Requested changes

- The customer map uses `flutter_map` with OpenStreetMap tiles. Google Maps and its web loader/key are removed because this app has no remaining Google Maps widgets. No Google warning is hidden or overlaid.
- The map has a fixed viewport; the Flutter address sheet handles its own touches and scrolling. Dragging the card does not pan or resize the map camera.
- Each opening requests foreground GPS permission and current location. **My location** retries. Tapping or moving the map selects a different location. Late GPS/geocoder responses cannot move a newer selection or overwrite edits made while waiting. Missing address fields are cleared instead of retaining a previous location's postcode.
- Search/reverse lookup uses Photon OpenStreetMap data through an authenticated Supabase Edge function. Address, city, state and postcode are filled when available. Federal territories such as Kuala Lumpur are handled. Unit/floor numbers and GPS/map inaccuracies still require customer review; there is no guarantee that all fields exist for every coordinate.
- Notifications: Chats replaces Mark all as read; swipe left exposes Pin/Unpin and Delete. The overflow menu provides the same accessible actions. Pins persist and sort first. Delete requires confirmation and keeps the booking unchanged.
- Profile: removed the top settings/chat icons, Edit your profile caption and Account & Security row. The photo still opens personal information. Settings: removed its top chat icon and duplicate My Addresses row.
- Account & Security: Delete your account replaces Sign out all devices. Normal logout remains in Settings.
- Booking and shared chat toolbars have no refresh icon. Pull down at the top or pull up at the bottom to refresh. Customer lists/forms use elastic overscroll, including short lists and the registration OTP page.

## Account deletion

The customer enters their **current password**, then confirms a permanent deletion dialog. `customer-delete-account` validates the bearer with Supabase Auth, verifies that password against the same Auth identity, and calls a service-only preparation RPC. It never accepts a target user ID or email from the client.

The preparation transaction locks the customer/booking rows, refuses unfinished bookings, open checkout attempts or unresolved disputes, deactivates and detaches the canonical application identity, removes saved addresses/notifications, clears profile fields and uploaded-image references, and redacts sent chat text/review text. Existing JWTs immediately lose application identity access. A restrictive Storage policy also denies writes by inactive accounts.

Storage files are removed through the **Storage API**, followed by hard deletion through the **Auth Admin API**. Auth identities and refresh sessions are removed. An anonymized internal customer row and transaction/rating references remain so completed provider bookings, payments and audit relationships are not broken. This retention is stated in the confirmation. The old email/password cannot sign in; registering again creates a fresh account and does not reconnect old records.

Deletion is staged because Auth and Storage are separate services. A private retry record permits cleanup to resume if storage/Auth temporarily fails. No password or token is stored there. The screen remains open on failure and keeps the original bearer only in memory for retry. Completion is never reported before the Auth deletion succeeds. If the user closes the app during failed cleanup, an administrator may need to resume the service-side cleanup using the private deletion record; the disabled account cannot re-enter customer screens.

## Deployment and external services

Applied migration: `20261004041056_customer_notification_pins_account_deletion.sql`. It was applied with nine regression suites inside a rollback-only fixture savepoint. It is already installed on the FYP project.

Deployed with JWT verification enabled:

- `customer-delete-account`
- `customer-geocode`

Both use built-in server credentials; no service-role key is shipped in Flutter. Geocoding additionally checks the canonical customer role. Queries are submitted explicitly or after a selected pin settles, with a shared two-second database rate gate and one-day cache. A successful lookup is not discarded if writing the cache fails. `PHOTON_URL` changes the server endpoint without an app update; `MAP_TILE_URL` can configure another compatible tile provider at build time.

Map tiles show visible [OpenStreetMap attribution](https://www.openstreetmap.org/copyright). The [OSM tile policy](https://operations.osmfoundation.org/policies/tiles/) requires attribution, application identification, caching and no bulk/offline downloading; this implementation uses the Flutter map client's normal caching and does not prefetch offline regions. [Photon's public service](https://photon.komoot.io/) permits fair-use projects but can throttle traffic and does not guarantee availability. These public services suit the FYP's modest use; use a provisioned or self-hosted service before a high-volume production rollout. [Photon API documentation](https://github.com/komoot/photon/blob/master/docs/api-v1.md).

Android declares coarse/fine foreground location permissions. iOS has a when-in-use purpose string. Web geolocation requires HTTPS or localhost and browser permission. There is no background location tracking. Use a full restart after `flutter pub get` because this change adds native geolocation plugins; hot reload alone is insufficient.

## Verification

- 47 Flutter tests, including Pixel 3a layouts, card/map gesture isolation, late GPS results, missing address fields, permission denial, notification pin/delete, deletion confirmation/failure and bottom-edge refresh.
- 12 server tests for authenticated password-confirmed deletion, spoofed target rejection, Storage-before-Auth ordering, retry failures, geocode parsing, permissions, throttling and empty cache-write responses.
- Nine SQL regression suites: existing admin, policy/index, analytics, customer Auth, customer modules, FPX, isolation, chat, plus the new account/notification suite. Fixtures rolled back.
- Live HTTP smoke checks used only temporary synthetic accounts: valid password login, wrong deletion password rejected, uploaded PNG removed, Auth hard deletion succeeded, old login rejected, old JWT denied, same email usable with a fresh identity, and real forward/reverse address lookup returning HTTP 200. Synthetic Auth users, public rows and uploaded files were removed afterward.
- Android debug APK built on Flutter 3.38.8 / Dart 3.10.7. Focused analysis has no errors or warnings; existing style/deprecation information remains.
- Existing Supabase notices for private tables with intentionally no client policies, the admin invitation preflight function, and [disabled leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remain; these are not new customer access grants.

Manual device acceptance: grant/deny GPS, reopen the map, drag the sheet, select another pin, verify address accuracy and save; test notification pin/delete after relaunch; test gestures on long and empty lists. Test permanent deletion only on a disposable account. Physical GPS accuracy and OS permission prompts still need a real-device check.

Updated renders with fixture data: [Profile](screenshots/customer-profile.png), [Settings](screenshots/customer-settings.png), [Account & Security](screenshots/customer-security.png).
