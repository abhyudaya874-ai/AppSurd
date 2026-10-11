import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import 'arena_state.dart';

/// Arena status page — pushed from Ask/Profile (Arena is no longer a tab).
/// Shows the jury lineup and explains what happens on the next submission.
class ArenaInfoScreen extends ConsumerWidget {
  const ArenaInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lineup = ref.watch(arenaLineupProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Arena')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Jury of ${lineup.length}',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final m in lineup)
                Text(
                  '${m.provider.label} · ${m.displayName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Submit proof on a task while Arena is on — every judge '
                'votes, and the verdict is computed in code.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
