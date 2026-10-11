import 'dart:async';

/// Per-provider token bucket: max 2 concurrent calls, a minimum spacing
/// between starts, and 429/Retry-After-aware backoff with jitter. Keeps
/// free-tier providers healthy; callers see wait states via [statuses].
class RateLimiter {
  static final _permits = <String, int>{};
  static final _lastStart = <String, DateTime>{};
  static final _backoffUntil = <String, DateTime>{};

  /// Live status stream for UI chips ('queued' / 'retrying in Ns').
  static final statuses = <String, String>{};

  static const _maxConcurrent = 2;
  static const _minSpacing = Duration(milliseconds: 400);

  /// Runs [job] under the provider's slot. Callers should map 429s onto
  /// [noteRateLimited] then retry through [run] again.
  static Future<T> run<T>(String providerId, Future<T> Function() job) async {
    // Wait out a recorded backoff window first.
    final until = _backoffUntil[providerId];
    if (until != null && until.isAfter(DateTime.now())) {
      final wait = until.difference(DateTime.now());
      statuses[providerId] =
          'Rate limited — retrying in ${wait.inSeconds + 1}s';
      await Future<void>.delayed(wait);
      statuses.remove(providerId);
    }
    // Concurrency gate.
    while ((_permits[providerId] ?? 0) >= _maxConcurrent) {
      statuses[providerId] = 'Queued';
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    statuses.remove(providerId);
    // Spacing.
    final last = _lastStart[providerId];
    if (last != null) {
      final gap = DateTime.now().difference(last);
      if (gap < _minSpacing) {
        await Future<void>.delayed(_minSpacing - gap);
      }
    }
    _permits[providerId] = (_permits[providerId] ?? 0) + 1;
    _lastStart[providerId] = DateTime.now();
    try {
      return await job();
    } finally {
      _permits[providerId] = _permits[providerId]! - 1;
    }
  }

  /// Record a 429 with optional Retry-After seconds; the next [run] waits.
  static void noteRateLimited(String providerId, {int? retryAfterSeconds}) {
    final secs =
        (retryAfterSeconds ?? 5) +
        DateTime.now().millisecond % 3; // tiny jitter
    _backoffUntil[providerId] = DateTime.now().add(Duration(seconds: secs));
  }

  /// Test hooks.
  static void reset() {
    _permits.clear();
    _lastStart.clear();
    _backoffUntil.clear();
    statuses.clear();
  }
}
