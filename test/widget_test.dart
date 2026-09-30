// Smoke test for the app root. Note that `flutter test` cannot run on this
// machine: Windows Application Control blocks flutter_tester.exe. The camera
// itself is only exercised on the emulator.

import 'package:flutter_test/flutter_test.dart';

import 'package:dashcam/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const DashCamApp());

    expect(find.text('Dash Cam'), findsOneWidget);
  });
}
