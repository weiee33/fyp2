import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp2/main.dart';

void main() {
  testWidgets('Pixel 3a entry exposes customer/provider portals only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 808);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LocalLifeApp());
    expect(find.text('Consumer Portal'), findsOneWidget);
    expect(find.text('Provider Portal'), findsOneWidget);
    expect(find.text('Admin Portal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
