# Home Serve branding and languages

The mobile app displays Home Serve on Android and iOS. Its existing package and bundle identifiers are unchanged so this remains an update to the same app. The original logo attachment was unavailable, so the committed artwork is an original orange house/checkmark design. `tool/generate_brand_assets.py` reproduces launcher, adaptive, monochrome, launch, and web images from the source design with Pillow.

Startup shows the native logo before Flutter, then an 850 ms scale/fade and a 300 ms transition to shared Login. Reduced-motion users get a static mark. Startup errors expose Retry; startup work is shared while a previous attempt is still pending so retries do not initialize Supabase twice.

## Language selection

Customer: Account Settings → Language / 语言 / Bahasa. Provider: language icon in My Profile. Signed-out users can use Login's language icon. Select English, 简体中文 or Bahasa Melayu, then Done. Back discards the draft. English is the first-launch default; the saved device preference applies to both account types and survives restarts and sign-out.

The mobile translation catalog covers navigation, forms, validation, booking/payment status, receipts, chat controls, notifications, customer AI controls, and provider screens. Flutter's locale delegates translate its date/time pickers and standard controls. Dates use the active locale while appointment times retain the existing Malaysia-time interpretation. Noto Sans SC supplies Chinese glyphs in the app and exported PDFs; its SIL Open Font License is bundled.

App-owned copy is translated at display boundaries. Stored names, service descriptions, addresses, messages, reviews, references, prices, database status values, and API identifiers are preserved. Historical AI replies are kept as written. New AI requests send a validated `en`, `zh` or `ms` locale; Gemini is instructed to reply in that language unless the customer requests another. Voice input selects the corresponding installed recognition language and reports unavailable input if the device lacks it.

The separate administrator website is outside this mobile preference. Operating-system permission dialogs, photo pickers, external bank pages and Stripe-hosted checkout follow their own supported languages and device/browser settings. This change does not modify gateway configuration or payment status rules.

## Maintaining translations

`assets/l10n/messages.json` maps an English source key to `[Simplified Chinese, Bahasa Melayu]`. Use `tr('Fixed copy')` and `tr('Booking {0}', [reference])`. Use explicit numbered arguments for variable text; do not wrap arbitrary user/provider content or API identifiers in `tr`. Translate app-owned status labels before inserting them into other templates.

`AppLanguage.watch(context)` subscribes a widget to language changes without resetting its route, form, or navigation state. `LanguageScope` wraps the application. Add new copy to both catalog columns and run:

```sh
python3 tool/check_localization.py
flutter test --no-pub
node --experimental-strip-types --test supabase/tests/customer_ai_edge.test.mjs supabase/tests/customer_account_edge.test.mjs supabase/tests/customer_recovery_edge.test.mjs supabase/tests/fpx_edge.test.mjs
```

The catalog check validates literal translation keys, matching placeholders and fixed display text that bypasses translation. It deliberately does not interpret dynamic/user-authored strings; additions to screen copy still need review. Widget tests cover persisted preferences, default English, saving versus cancelling a selection, updates to an existing route, larger text on narrow screens, startup retry/reduced motion, and authoritative booking values. `app_language_visual_test.dart` checks English/Chinese/Malay login, settings, language, booking, details, and receipt screens plus PDF generation. See [shared mobile authentication](shared-mobile-auth.md) for role routing and recovery.

Optional screenshot/PDF capture:

```sh
flutter test test/app_language_visual_test.dart --dart-define=CAPTURE_UI=true --dart-define=FLUTTER_FONT_ROOT=<flutter-sdk>/bin/cache/artifacts/material_fonts
```

Capture output is ignored under `.tools/customer-ui/`. Test receipts contain fixture data and are not customer records.

## Original branding rollout

This branch includes teammate commit `e9c99bf` (provider Schedule/Profile). The provider's BookingService RPC implementation is retained; integration changes affect display copy and language access. No database migration or payment-gateway change is required. Deploy `customer-assistant` before distributing the updated app because it adds an optional, validated `locale` request field; older clients remain supported. The deployed function retains JWT verification and server-side booking confirmation controls.

Validated on Windows with Flutter 3.38.8 / Dart 3.10: automated Flutter/backend tests, mobile widget snapshots, three one-page PDF receipts with Chinese glyphs and payment references, and Android debug compilation. The iOS launcher/launch artwork and localized permission resource configuration are included but require an Xcode build and device verification on macOS. No physical phone was attached during these checks.
