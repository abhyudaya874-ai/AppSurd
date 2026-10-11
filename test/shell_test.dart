// Widget test: swipe-right on Home reveals the sidebar; nav rows are
// visible; tapping one navigates and closes the drawer; back closes it
// before popping.

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

  /// The content layer is a Transform that slides right when the drawer is
  /// open — translate.x > 0 means "open".
  Finder drawerOpen() => find.byWidgetPredicate(
    (w) => w is Transform && w.transform.getTranslation().x > 0.5,
  );

  testWidgets('swipe-right opens drawer, nav works, back closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppShell())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Home content visible; drawer closed.
    expect(find.text('What will you prove today?'), findsOneWidget);
    expect(drawerOpen(), findsNothing);

    // Swipe right on Home → drawer slides open.
    await tester.dragFrom(const Offset(20, 400), const Offset(320, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(drawerOpen(), findsWidgets);

    // All nav rows visible.
    for (final label in ['Home', 'Tasks', 'Schedule', 'Ask', 'Profile']) {
      expect(find.text(label), findsWidgets, reason: '$label nav row missing');
    }
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Receipts'), findsWidgets); // brand + home wordmark

    // Tap Schedule → navigates and auto-closes.
    await tester.tap(find.text('Schedule').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(drawerOpen(), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(navIndexProvider), 2);

    // Open via the avatar button on a non-Home page.
    await tester.tap(find.byType(MenuAvatar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(drawerOpen(), findsWidgets);

    // Android back closes the drawer first instead of popping the app.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(drawerOpen(), findsNothing);
  });
}
