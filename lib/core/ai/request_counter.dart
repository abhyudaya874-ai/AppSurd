import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-provider call counter for the session — surfaced in Settings to spot
/// free-tier pressure (429s) during development and demos. Static so the
/// const router can bump it without a container reference.
abstract final class RequestCounterStats {
  static final counts = <String, int>{};
  static void bump(String providerId) =>
      counts[providerId] = (counts[providerId] ?? 0) + 1;
}

final requestCounterProvider = Provider<Map<String, int>>(
  (ref) => Map.of(RequestCounterStats.counts),
);
