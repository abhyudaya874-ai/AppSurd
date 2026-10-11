// Widget test for the signature pill: collapsed state renders, tapping opens
// the morphing overlay card, the strength slider shows all four detents.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:receipts/features/model_picker/model_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init('/tmp/receipts_pill_test_hive');
  });

  testWidgets('pill opens picker card with 4 tier stops', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: ModelPill())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed pill shows the preset label even with no keys configured.
    expect(find.textContaining('Balanced'), findsOneWidget);

    await tester.tap(find.byType(ModelPill));
    await tester.pumpAndSettle();

    // The expanded card shows all four detents and the Custom row.
    for (final label in ['Swift', 'Balanced', 'Smart', 'Deep']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Custom'), findsOneWidget);
  });
}
