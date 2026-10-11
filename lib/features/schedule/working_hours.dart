import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// One availability window in minutes-of-day (0–1440), e.g. 09:00–17:00.
class TimeRange {
  const TimeRange(this.startMin, this.endMin);

  /// Minutes since midnight (inclusive).
  final int startMin;

  /// Minutes since midnight (exclusive).
  final int endMin;

  int get length => endMin - startMin;

  bool contains(int minute) => minute >= startMin && minute < endMin;

  bool overlaps(TimeRange other) =>
      startMin < other.endMin && other.startMin < endMin;

  Map<String, dynamic> toJson() => {'s': startMin, 'e': endMin};

  factory TimeRange.fromJson(Map<String, dynamic> json) =>
      TimeRange((json['s'] as num).toInt(), (json['e'] as num).toInt());
}

/// Which weekdays (1=Mon … 7=Sun) are "on" and their working windows.
/// Persisted in the receipts_settings box so the schedule shading and the
/// auto-scheduler survive restarts.
class WorkingHours {
  const WorkingHours(this.days);

  /// weekday → list of ranges (empty list = day enabled but no windows yet;
  /// absent key = day off).
  final Map<int, List<TimeRange>> days;

  bool isEnabled(int weekday) => days.containsKey(weekday);

  List<TimeRange> rangesFor(int weekday) => days[weekday] ?? const [];

  /// Is [minute] of [weekday] inside any working window?
  bool covers(int weekday, int minute) =>
      rangesFor(weekday).any((r) => r.contains(minute));

  WorkingHours copy() => WorkingHours({
    for (final e in days.entries) e.key: [...e.value],
  });

  Map<String, dynamic> toJson() => {
    for (final e in days.entries)
      '${e.key}': [for (final r in e.value) r.toJson()],
  };

  factory WorkingHours.fromJson(Map<String, dynamic> json) => WorkingHours({
    for (final e in json.entries)
      int.parse(e.key): [
        for (final r in (e.value as List))
          TimeRange.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
  });
}

/// Validation for the editor: every range must be end>start and ranges must
/// not overlap. Returns an error string, or null when valid.
String? validateRanges(List<TimeRange> ranges) {
  for (final r in ranges) {
    if (r.endMin <= r.startMin) return 'End must be after start';
    if (r.startMin < 0 || r.endMin > 1440) return 'Outside the day';
  }
  final sorted = [...ranges]..sort((a, b) => a.startMin - b.startMin);
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMin < sorted[i - 1].endMin) {
      return 'Ranges overlap';
    }
  }
  return null;
}

/// Persisted working hours. Default: weekdays on at 09:00–18:00 so the
/// auto-scheduler has somewhere to put tasks before the user customises it.
final workingHoursProvider =
    NotifierProvider<WorkingHoursNotifier, WorkingHours>(
      WorkingHoursNotifier.new,
    );

class WorkingHoursNotifier extends Notifier<WorkingHours> {
  static const _boxName = 'receipts_settings';
  static const _key = 'workingHours';

  @override
  WorkingHours build() {
    _load();
    return WorkingHours({
      for (var d = 1; d <= 5; d++) d: [const TimeRange(9 * 60, 18 * 60)],
    });
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final raw = box.get(_key);
    if (raw is Map) {
      state = WorkingHours.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> set(WorkingHours hours) async {
    state = hours;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, hours.toJson());
  }
}
