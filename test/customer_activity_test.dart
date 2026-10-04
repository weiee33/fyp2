import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/Customer/screens/profile/customer_saved_addresses_screen.dart';
import 'package:fyp2/Customer/screens/auth/customer_forgot_password_screen.dart';
import 'package:fyp2/Customer/widgets/customer_unread_badge.dart';
import 'package:fyp2/Customer/services/customer_recovery_service.dart';
import 'customer_ux_test.dart' as fixture;

class SavedAddresses extends fixture.Addresses {
  final rows = <Map<String, dynamic>>[
    {
      'address_id': 'one',
      'label': 'Home',
      'address_line': 'First address',
      'is_default': true,
    },
    {
      'address_id': 'two',
      'label': 'Office',
      'address_line': 'Second address',
      'is_default': false,
    },
  ];
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> getSavedAddresses() async =>
      rows.map((r) => Map<String, dynamic>.from(r)).toList();
  @override
  Future<void> setDefaultAddress(String id, String address) async {
    if (fail) throw const FormatException('Address unavailable');
    for (final r in rows) {
      r['is_default'] = r['address_id'] == id;
    }
  }

  @override
  Future<void> deleteAddress(String id) async {
    if (fail) throw const FormatException('Address unavailable');
    rows.removeWhere((r) => r['address_id'] == id);
  }
}

class Recovery extends CustomerRecoveryService {
  int checks = 0, sends = 0;
  bool rejected = false;
  @override
  Future<void> verifyCurrentPassword(String email, String password) async {
    checks++;
    if (password != 'correct-current')
      throw const FormatException('Current password is incorrect.');
  }

  @override
  Future<void> requestCode(String email) async {
    if (rejected)
      throw const FormatException('No registered customer account.');
    sends++;
  }

  @override
  Future<void> dispose() async {}
}

class Counts extends CustomerActivityCounts {
  int refs = 0;
  @override
  void acquire() {
    refs++;
  }

  @override
  void release() {
    refs--;
  }

  void update(String kind, int count) {
    counts = {kind: count};
    notifyListeners();
  }
}

void main() {
  setUpAll(() async {
    var fontRoot = const String.fromEnvironment('FLUTTER_FONT_ROOT');
    if (fontRoot.isEmpty) {
      var directory = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 7 && fontRoot.isEmpty; i++) {
        for (final relative in [
          'material_fonts',
          'artifacts/material_fonts',
          'bin/cache/artifacts/material_fonts',
        ]) {
          final candidate = '${directory.path}/$relative';
          if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
            fontRoot = candidate;
            break;
          }
        }
        directory = directory.parent;
      }
    }
    expect(
      fontRoot,
      isNotEmpty,
      reason: 'Use the Flutter SDK fonts for realistic layout dimensions.',
    );
    if (fontRoot.isNotEmpty) {
      for (final e in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(e.key)
          ..addFont(
            File(
              '$fontRoot/${e.value}',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await loader.load();
      }
    }
  });
  testWidgets(
    'default and delete do not report a failure after successful mutations',
    (t) async {
      fixture.pixel(t);
      final s = SavedAddresses();
      await t.pumpWidget(fixture.app(CustomerSavedAddressesScreen(service: s)));
      await t.pumpAndSettle();
      await t.tap(find.text('Set as default'));
      await t.pumpAndSettle();
      expect(s.rows.last['is_default'], true);
      expect(find.text('Address updated successfully.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').last);
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(s.rows.length, 1);
      expect(find.text('Address updated successfully.'), findsOneWidget);
      expect(find.textContaining('Could not update'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'failed mutation preserves saved address and shows actual error',
    (t) async {
      fixture.pixel(t);
      final s = SavedAddresses()..fail = true;
      await t.pumpWidget(fixture.app(CustomerSavedAddressesScreen(service: s)));
      await t.pumpAndSettle();
      await t.tap(find.text('Set as default'));
      await t.pumpAndSettle();
      expect(find.text('Address unavailable'), findsOneWidget);
      expect(s.rows.first['is_default'], true);
    },
  );
  for (final size in [const Size(393, 808), const Size(360, 720)]) {
    testWidgets(
      'address panel save and attribution visible without dragging at $size',
      (t) async {
        fixture.pixel(t);
        t.view.physicalSize = size;
        await t.pumpWidget(fixture.app(fixture.map(fixture.Addresses())));
        await fixture.ready(t);
        expect(
          find.text('Save & Select Address').hitTestable(),
          findsOneWidget,
        );
        expect(
          find.text('© OpenStreetMap contributors').hitTestable(),
          findsOneWidget,
        );
        expect(
          t.getTopLeft(find.text('My location')).dy,
          greaterThan(
            t.getTopLeft(find.byKey(const ValueKey('address-details-card'))).dy,
          ),
        );
        expect(
          find.text('Set as default service address').hitTestable(),
          findsOneWidget,
        );
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          await t.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '.tools/customer-ui/address-panel-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('badge follows incoming and read counts and hides zero', (
    t,
  ) async {
    final c = Counts();
    await t.pumpWidget(
      fixture.app(
        CustomerUnreadBadge(
          kind: 'chats',
          controller: c,
          child: const Icon(Icons.chat),
        ),
      ),
    );
    c.update('chats', 3);
    await t.pump();
    expect(find.text('3'), findsOneWidget);
    c.update('chats', 2);
    await t.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    c.update('chats', 0);
    await t.pump();
    expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, false);
    await t.pumpWidget(const SizedBox());
    expect(c.refs, 0);
  });
  testWidgets(
    'signed-in password change checks current password before requesting OTP',
    (t) async {
      fixture.pixel(t);
      final s = Recovery();
      await t.pumpWidget(
        fixture.app(
          CustomerForgotPasswordScreen(
            initialEmail: 'known@example.invalid',
            requireCurrentPassword: true,
            service: s,
          ),
        ),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'wrong-current',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'valid-new-password',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'valid-new-password',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'does-not-match',
      );
      await t.ensureVisible(find.text('Confirm change password'));
      await t.tap(find.text('Confirm change password'));
      await t.pumpAndSettle();
      expect(s.checks, 0);
      expect(s.sends, 0);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'valid-new-password',
      );
      await t.ensureVisible(find.text('Confirm change password'));
      await t.tap(find.text('Confirm change password'));
      await t.pumpAndSettle();
      expect(s.checks, 1);
      expect(s.sends, 0);
      expect(find.text('Current password is incorrect.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Current password'),
        'correct-current',
      );
      await t.ensureVisible(find.text('Confirm change password'));
      await t.tap(find.text('Confirm change password'));
      await t.pumpAndSettle();
      expect(s.sends, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unknown recovery email remains on form without OTP success message',
    (t) async {
      fixture.pixel(t);
      final s = Recovery()..rejected = true;
      await t.pumpWidget(fixture.app(CustomerForgotPasswordScreen(service: s)));
      expect(find.text('Current password'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'unknown@example.invalid',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'valid-new-password',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'valid-new-password',
      );
      await t.tap(find.text('Confirm change password'));
      await t.pumpAndSettle();
      expect(s.sends, 0);
      expect(find.text('No registered customer account.'), findsOneWidget);
      expect(find.text('Email verification code'), findsNothing);
    },
  );
}
