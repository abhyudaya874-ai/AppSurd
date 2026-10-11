import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../model_picker/model_selection.dart';
import '../model_picker/strength_slider.dart';
import 'arena_models.dart';
import 'arena_state.dart';

/// The picker's Arena body: multi-select lineup (min 2, max 4) grouped by
/// provider, plus the Strictness slider reusing the strength widget.
class ArenaPanel extends ConsumerStatefulWidget {
  const ArenaPanel({super.key});

  @override
  ConsumerState<ArenaPanel> createState() => _ArenaPanelState();
}

class _ArenaPanelState extends ConsumerState<ArenaPanel> {
  Strictness? _preview;

  @override
  void initState() {
    super.initState();
    // Empty lineup in arena mode → seed a diverse default jury so the
    // feature is reachable even before keys exist (Demo Mode runs canned).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = ref.read(modelSelectionProvider);
      if (sel.arenaMode && sel.arenaLineup.length < 2) {
        final n = ref.read(modelSelectionProvider.notifier);
        for (final id in defaultLineup()) {
          n.toggleArenaModel(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final sel = ref.watch(modelSelectionProvider);
    final keys = ref.watch(configuredKeysProvider).value ?? const {};
    final shown = _preview ?? sel.strictness;
    // Strictness maps onto a cool→hot ramp (calm fair → red brutal).
    final detents = [
      theme.colorScheme.tertiary,
      theme.colorScheme.primary,
      tints.groq,
      theme.colorScheme.error,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              Text('Jury lineup', style: theme.textTheme.titleSmall),
              const Spacer(),
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                style: theme.textTheme.labelSmall!.copyWith(
                  color: sel.arenaLineup.length >= 2
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                child: Text('${sel.arenaLineup.length}/4'),
              ),
            ],
          ),
        ),

        // Multi-select, grouped by provider.
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              for (final provider in AiProvider.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xxs,
                  ),
                  child: Text(
                    provider.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tints.forId(provider.id),
                    ),
                  ),
                ),
                for (final m in kModelCatalog.where(
                  (m) => m.provider == provider,
                ))
                  _ModelCheckRow(
                    model: m,
                    selected: sel.arenaLineup.contains(m.id),
                    locked: !keys.containsKey(provider),
                    disableDeselect:
                        sel.arenaLineup.contains(m.id) &&
                        sel.arenaLineup.length <= 2,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(modelSelectionProvider.notifier)
                          .toggleArenaModel(m.id);
                    },
                  ),
              ],
            ],
          ),
        ),

        // Strictness — same custom slider, different meaning.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              StrengthSlider(
                value: shown.index.toDouble(),
                detentColors: detents,
                onChanged: (v) =>
                    setState(() => _preview = Strictness.values[v.round()]),
                onChangeEnd: (v) {
                  ref
                      .read(modelSelectionProvider.notifier)
                      .setStrictness(Strictness.values[v.round()]);
                  setState(() => _preview = null);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final s in Strictness.values)
                    AnimatedDefaultTextStyle(
                      duration: AppMotion.fast,
                      style:
                          (s == shown
                                  ? theme.textTheme.labelLarge
                                  : theme.textTheme.labelSmall)!
                              .copyWith(
                                color: s == shown
                                    ? detents[s.index]
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                      child: Text(s.name),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ],
    );
  }
}

/// One selectable model row — checkbox + strength dots + badges; dims and
/// routes to Settings via long-press semantics when the provider has no key.
class _ModelCheckRow extends StatelessWidget {
  const _ModelCheckRow({
    required this.model,
    required this.selected,
    required this.locked,
    required this.disableDeselect,
    required this.onTap,
  });

  final ModelSpec model;
  final bool selected;
  final bool locked;
  final bool disableDeselect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = (theme.extension<ProviderTints>() ?? const ProviderTints())
        .forId(model.provider.id);
    return Opacity(
      opacity: locked ? 0.4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: locked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? tint : tint.withValues(alpha: 0.12),
                  border: Border.all(color: tint, width: 1.4),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.displayName, style: theme.textTheme.bodyMedium),
                    Text(
                      '${model.tier.label} · ${model.blurb}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (model.supportsVision)
                Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              if (model.supportsReasoning)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.lock_outline,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (disableDeselect)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: 'Arena needs at least 2 judges',
                    child: Icon(
                      Icons.push_pin_outlined,
                      size: 13,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
