import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tasks/tasks_provider.dart';
import 'animated_app_icon.dart';

/// The header counter showing the Integrity Score (50 + Σ integrityDelta).
/// Lives in core so both Home and Tasks headers can show it.
class IntegrityChip extends ConsumerWidget {
  const IntegrityChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(integrityScoreProvider);
    final theme = Theme.of(context);
    return Chip(
      avatar: AnimatedAppIcon(
        type: AppIconType.shield,
        active: score > 50,
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text('$score', style: theme.textTheme.labelLarge),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
    );
  }
}
