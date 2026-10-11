import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import 'model_selection.dart';
import 'resolved_model.dart';
import '../settings/settings_screen.dart';

/// The "Custom ›" sub-panel: pick an exact model (grouped by provider), set
/// reasoning effort (only where supported), and bias speed toward Groq.
class CustomPanel extends ConsumerWidget {
  const CustomPanel({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(modelSelectionProvider);
    final keys = ref.watch(configuredKeysProvider).value ?? const {};
    final alive = ref.watch(aliveModelsProvider).value ?? const {};
    final resolved = ref.watch(resolvedModelProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: [
        // ---- Model picker, grouped by provider ----
        _SectionLabel('Model'),
        for (final provider in AiProvider.values)
          _ProviderGroup(
            provider: provider,
            hasKey: keys.containsKey(provider),
            alive: alive[provider],
            selectedId: selection.customModelId,
            onPick: (id) =>
                ref.read(modelSelectionProvider.notifier).setCustomModel(id),
          ),

        // ---- Reasoning effort (hidden when unsupported) ----
        if (resolved?.supportsReasoning ?? false) ...[
          _SectionLabel('Reasoning'),
          Row(
            children: [
              for (final level in ReasoningLevel.values)
                _ChoiceChipX(
                  label: level.name[0].toUpperCase() + level.name.substring(1),
                  selected: selection.reasoning == level,
                  onTap: () => ref
                      .read(modelSelectionProvider.notifier)
                      .setReasoning(level),
                ),
            ],
          ),
        ],

        // ---- Speed bias ----
        _SectionLabel('Speed'),
        Row(
          children: [
            _ChoiceChipX(
              label: 'Normal',
              selected: selection.speed == SpeedPref.normal,
              onTap: () => ref
                  .read(modelSelectionProvider.notifier)
                  .setSpeed(SpeedPref.normal),
            ),
            _ChoiceChipX(
              label: 'Fast · Groq first',
              selected: selection.speed == SpeedPref.fast,
              onTap: () => ref
                  .read(modelSelectionProvider.notifier)
                  .setSpeed(SpeedPref.fast),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () {
            ref.read(modelSelectionProvider.notifier).setCustomModel(null);
            onBack();
          },
          icon: const Icon(Icons.undo_rounded, size: 16),
          label: const Text('Return to presets'),
        ),
      ],
    );
  }
}

/// Small section heading inside the custom panel.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

/// Selection chip used for reasoning/speed rows.
class _ChoiceChipX extends StatelessWidget {
  const _ChoiceChipX({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.18)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// A provider header plus its alive models; dimmed + lock affordance when no
/// key is configured (taps route to Settings).
class _ProviderGroup extends StatelessWidget {
  const _ProviderGroup({
    required this.provider,
    required this.hasKey,
    required this.alive,
    required this.selectedId,
    required this.onPick,
  });

  final AiProvider provider;
  final bool hasKey;
  final Set<String>? alive;
  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.extension<ProviderTints>()!.forId(provider.id);
    final models = kModelCatalog
        .where((m) => m.provider == provider)
        .where((m) => alive == null || alive!.contains(m.id))
        .toList();

    return Opacity(
      opacity: hasKey ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasKey
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen()),
                    ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(provider.label, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (!hasKey)
                    Row(children: [
                      Icon(Icons.lock_outline,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('add key',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                ],
              ),
            ),
          ),
          for (final m in models)
            InkWell(
              onTap: hasKey ? () => onPick(m.id) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.displayName,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.supportsVision)
                      Icon(Icons.visibility_outlined,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                    if (m.supportsReasoning)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.psychology_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      selectedId == m.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                      color: selectedId == m.id
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
