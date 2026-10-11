// UI-level check: the evidence sheet renders all four capture modes and the
// segmented control slides between them. (Full submit→verdict is exercised
// headlessly in tasks_persistence_test + on device — widget tests fake the
// async zone so real disk/network can't flow through.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:receipts/features/tasks/evidence_sheet.dart';
import 'package:receipts/features/tasks/task_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => Hive.init('/tmp/receipts_flow_test_hive'));

  testWidgets('evidence sheet: 4 modes switch with sliding control',
      (tester) async {
    final task = Task(
      id: 't1',
      title: 'Probe',
      description: '',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: EvidenceSheet(task: task)),
      ),
    ));
    await tester.pumpAndSettle();

    for (final label in ['URL', 'Shot', 'Text', 'Commit']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Verify it'), findsOneWidget);

    // Switch to Text — multiline input appears.
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notes), findsWidgets);
  });
}
