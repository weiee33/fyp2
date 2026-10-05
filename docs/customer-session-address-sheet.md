# Password cancellation and address sheet

This supersedes the recovery-client and fixed-footer descriptions in `customer-address-activity-password.md`.

## Why leaving Change Password broke the customer screens

GoTrue 2.27.2 creates a project-wide browser Auth BroadcastChannel for every client, including clients with `autoRefreshToken: false` and no persistent storage. The temporary client used to check the current password therefore broadcast its sign-in and local sign-out to the main app. That cleared the main session. Subsequent customer RPCs ran as anonymous and correctly returned permission denied.

Live permissions for `account_identity()` and `customer_bookings(integer, integer)` grant execution to authenticated users and deny anonymous users. No SQL privilege relaxation or database migration is needed for this fix.

`CustomerRecoveryService` now uses HTTP requests with in-memory temporary tokens. It never constructs a GoTrue client, stores a session in the main client, or emits Auth broadcast events. Current-password checking revokes only its temporary session. Leaving the page waits for an in-flight check to return, cleans up its temporary token, and prevents the next stage. A disposed page does not request OTP or access its controllers.

The password only changes after recovery OTP verification and a canonical customer-role check. Back navigation is blocked while that final submission is in flight so the customer cannot leave during an ambiguous commit. Global session revocation occurs only after a successful password update. The app then asks the customer to sign in again. An abandoned change keeps the old password and main session.

## Address picker

- One draggable sheet contains search, attribution, address details and Save. The map viewport does not resize as the sheet moves.
- Three snap positions: collapsed search dock, middle (55%, the initial position), and expanded (94% of the available body). The expanded sheet stays below the app bar.
- Search remains pinned within the sheet and expands it when focused. Save follows the default-address switch in the scrolling form, with no separate bottom footer or large forced gap.
- The compact OpenStreetMap credit stays visible in the search header even when collapsed. It travels with the sheet and links to the copyright page.
- The initial/recentered pin is positioned in the upper quarter of the map so the middle sheet does not conceal it. Sheet drags do not pan the map. Address fields remain editable when reverse geocoding cannot supply a component.

## Verification

Run the ordinary Flutter suite and the browser-specific cancellation suite separately:

```powershell
flutter test --no-pub
flutter test --no-pub --platform chrome test/customer_recovery_web_test.dart
flutter build apk --debug --no-pub
```

The browser suite uses the real Supabase SDK main client with mocked HTTP responses. It checks cancellation after a password check, during a password check, and during OTP verification: the main token stays unchanged, no main Auth event occurs, only the temporary session is revoked, no password update is sent, and a main-client identity RPC remains authenticated. This specifically covers the browser BroadcastChannel regression; it does not send real email or alter customer accounts.

Widget tests cover navigation away during validation and the sheet's collapsed/expanded positions at 393×808 and 360×720 using real font metrics. GitHub Actions runs the browser suite on Linux because the local Flutter 3.38.8 Windows web-test asset handler returns 404 for CanvasKit paths before tests start. No local SDK changes are required.

Device acceptance should include actual GPS permissions, keyboard editing, map panning, and Gmail OTP delivery. These depend on device/network services and are not established by mocked tests. Fully restart the updated app; if the previous version already cleared the session, sign in once again with the unchanged password.
