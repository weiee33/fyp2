import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/main.dart';
import 'package:fyp2/shared/mobile_auth_service.dart';

class SignedOutAuth extends MobileAuthService {
  @override
  Future<MobileAccountRole?> restoreSession() async => null;
}

void main() {
  testWidgets('Pixel 3a opens shared login without a role selection step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 808);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalLifeApp(initialize: () async {}, authService: SignedOutAuth()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsNWidgets(2));
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Consumer Portal'), findsNothing);
    expect(find.text('Provider Portal'), findsNothing);
    expect(find.text('Admin Portal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
