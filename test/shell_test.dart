// Widget test: the shell renders 5 tabs with always-visible icons, and
// tapping one switches pages (IndexedStack keeps them all mounted). Labels
// expand only beside the active icon, so they appear after the tap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:receipts/features/shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Hive.init('/tmp/receipts_test_hive_shell');
  });

  testWidgets('shell shows 5 tabs and switches', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppShell())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // All five tab icons are always visible.
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    // Home is the default — label expanded + serif headline on screen.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('What will you prove today?'), findsOneWidget);

    // Tap the Tasks tab icon → its label + header show.
    await tester.tap(find.byIcon(Icons.checklist_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tasks'), findsWidgets);

    // Tap Ask → its label + AppBar show.
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ask'), findsWidgets);
  });
}
