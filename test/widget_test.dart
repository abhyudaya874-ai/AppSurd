// Smoke test: the app boots into the splash screen without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:receipts/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Point Hive at a throwaway directory so tests don't need a device path.
    Hive.init('/tmp/receipts_test_hive');
  });

  testWidgets('app boots to splash', (tester) async {
    await tester.pumpWidget(const ReceiptsApp());
    expect(find.text('Receipts'), findsOneWidget);
  });
}
