import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import 'working_hours.dart';

/// Weekly availability editor (ref: recording 4): one row per weekday with a
/// switch; an enabled day expands to From/To time ranges with ✕ and
/// "+ Add more" (each new range starts where the last ended). Validation
/// errors show inline and block nothing — invalid ranges are dropped on save.
class WorkingHoursEditor extends ConsumerStatefulWidget {
  const WorkingHoursEditor({super.key});

  @override
  ConsumerState<WorkingHoursEditor> createState() =>
      _WorkingHoursEditorState();
}

class _WorkingHoursEditorState extends ConsumerState<WorkingHoursEditor> {
  static const _names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday'
  ];

  String _fmt(int min) =>
      '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  Future<void> _edit(int weekday, int index, bool isStart) async {
    final hours = ref.read(workingHoursProvider).copy();
    final ranges = hours.days[weekday] ?? [];
    if (index >= ranges.length) return;
    final r = ranges[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: (isStart ? r.startMin : r.endMin) ~/ 60,
          minute: (isStart ? r.startMin : r.endMin) % 60),
    );
    if (picked == null) return;
    final m = picked.hour * 60 + picked.minute;
    ranges[index] =
        isStart ? TimeRange(m, r.endMin) : TimeRange(r.startMin, m);
    HapticFeedback.selectionClick();
    await ref.read(workingHoursProvider.notifier).set(hours);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hours = ref.watch(workingHoursProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Working hours')),
      body: ConstrainedContent(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Blocks only land inside these windows — both for drag-drop '
              'hints and the Auto scheduler. Non-working hours stay shaded.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var d = 1; d <= 7; d++) _dayRow(theme, hours, d),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(ThemeData theme, WorkingHours hours, int d) {
    final on = hours.isEnabled(d);
    final ranges = hours.rangesFor(d);
    final error = on ? validateRanges(ranges) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outline)),
      child: Column(children: [
        SwitchListTile(
          title: Text(_names[d - 1], style: theme.textTheme.titleSmall),
          value: on,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            final next = hours.copy();
            if (v) {
              next.days[d] = [const TimeRange(9 * 60, 17 * 60)];
            } else {
              next.days.remove(d);
            }
            ref.read(workingHoursProvider.notifier).set(next);
          },
        ),
        AnimatedSize(
          duration: AppMotion.of(context, AppMotion.base),
          curve: AppMotion.standard,
          child: on
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < ranges.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(children: [
                            Text('From',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: theme.colorScheme
                                            .onSurfaceVariant)),
                            const SizedBox(width: AppSpacing.xs),
                            _timeChip(theme, _fmt(ranges[i].startMin),
                                () => _edit(d, i, true)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs),
                              child: Text('To',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(
                                          color: theme.colorScheme
                                              .onSurfaceVariant)),
                            ),
                            _timeChip(theme, _fmt(ranges[i].endMin),
                                () => _edit(d, i, false)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Remove range',
                              icon: const Icon(Icons.close_rounded,
                                  size: 18),
                              onPressed: () {
                                final next = hours.copy();
                                next.days[d]!.removeAt(i);
                                ref
                                    .read(workingHoursProvider.notifier)
                                    .set(next);
                              },
                            ),
                          ]),
                        ),
                      if (error != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(error,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error)),
                        ),
                      TextButton.icon(
                        onPressed: () {
                          final next = hours.copy();
                          final last = next.days[d]!.isEmpty
                              ? 9 * 60
                              : next.days[d]!.last.endMin;
                          final start = last + 15 < 1440 ? last : 9 * 60;
                          next.days[d]!.add(TimeRange(
                              start, (start + 60).clamp(0, 1440)));
                          ref
                              .read(workingHoursProvider.notifier)
                              .set(next);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add more'),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _timeChip(ThemeData theme, String label, VoidCallback onTap) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 6),
          child: Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
      ),
    );
  }
}
