# Customer UI polish

This change follows the 21 customer screenshots supplied on 15 October 2026.

- Center the profile avatar and name; shorten the Reviews shortcut and remove the specified explanatory text from profile, settings, language, security, and chat screens.
- Use title case for the requested screen titles. Language selection retains its explicit Save action and persisted English, Chinese, and Bahasa Melayu preferences.
- Bound the Malaysian phone prefix vertically so the editor remains compact; retain number normalization and validation.
- Split Reviews into swipeable Ready To Review and Your Reviews tabs, retaining refresh, pagination, review submission, and booking navigation.
- Present account deletion with a prominent irreversible-action warning, prerequisite details, password entry, and a Keep My Account action. Existing confirmation and server checks still apply.
- Align booking/payment badges and receipt actions; use equal service-category card dimensions and aligned icons.
- Use a shared rainbow AI mark and a single bottom-navigation surface. Center the assistant header, move new-chat access exclusively into history, and display history as a centered dialog that accommodates the keyboard.
- Remove photo-viewer captions while retaining accessible position announcements, swipe navigation, previous/next controls, and pinch zoom.

## Verification

The Flutter suite covers navigation, phone editing, review swipes, payment-status alignment, deletion guards, chat/gallery behavior, and existing booking/payment contracts. Additional visual fixtures cover all three languages at 360 px, and reviews/phone entry at 320 px with 1.4x text. Translation keys are checked with `python tool/check_localization.py`.

To regenerate screenshots under `.tools/customer-ui`, run Flutter tests with `--dart-define=CAPTURE_UI=true`. Set `FLUTTER_FONT_ROOT` to Flutter's `bin/cache/artifacts/material_fonts` directory to render icon fonts in captures.

Physical-device interaction remains a manual acceptance step using the debug APK. This change does not modify provider business logic, database migrations, or payment/AI backend configuration.
