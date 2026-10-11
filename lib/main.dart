import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app.dart';

/// Entry point: init local storage, then run inside a ProviderScope so all
/// feature state lives in Riverpod notifiers.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/ — never fetch at runtime (offline-proof demo).
  GoogleFonts.config.allowRuntimeFetching = false;
  await Hive.initFlutter();
  runApp(const ProviderScope(child: ReceiptsApp()));
}
