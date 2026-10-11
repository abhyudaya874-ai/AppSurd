import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../arena/arena_panel.dart';
import '../settings/settings_screen.dart';
import 'model_picker_overlay.dart';
import 'custom_panel.dart';
import 'model_selection.dart';
import 'resolved_model.dart';
import 'strength_slider.dart';

/// Contents of the expanded picker card: header (routed model + blurb that
/// cross-fades as you drag), the strength slider with tier labels, and a
/// "Custom ›" row that slides in the model/reasoning/speed sub-panel.
class PickerCard extends ConsumerStatefulWidget {
  const PickerCard({super.key});

  @override
  ConsumerState<PickerCard> createState() => _PickerCardState();
}

class _PickerCardState extends ConsumerState<PickerCard> {
  Tier? _preview; // tier under the thumb while dragging
  bool _customOpen = false;

  ModelSpec? _primaryFor(Tier tier) {
    final keys = ref.read(configuredKeysProvider).value ?? const {};
    final alive = ref.read(aliveModelsProvider).value ?? const {};
    return const ModelRouter()
        .plan(tier: tier, keys: keys, aliveIds: alive)
        .candidates
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = ref.watch(modelSelectionProvider);
    final resolved = ref.watch(resolvedModelProvider);
    final tints = ref.watch(tierTintsProvider);

    final shownTier = _preview ?? selection.preset;
    // With a custom pick, the header shows that model; otherwise the routed
    // primary for the shown (possibly previewed) tier.
    final shownModel = selection.customModelId != null
        ? kModelCatalog
              .where((m) => m.id == selection.customModelId)
              .firstOrNull
        : (_preview == null ? resolved : _primaryFor(shownTier));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Header: model name + cross-fading blurb ----
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Column(
                    key: ValueKey(shownModel?.id ?? 'none'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shownModel?.displayName ?? 'No model available',
                        style: theme.textTheme.titleLarge,
                      ),
                      if (shownModel == null)
                        InkWell(
                          onTap: () {
                            // Close the picker first — it floats above the
                            // Navigator, so Settings would push behind it.
                            PickerScope.of(context)?.dismiss();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Add a key in Settings →',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${shownModel.provider.label} · ${shownModel.blurb}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ---- Body: slider mode or custom panel ----
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.base,
            switchInCurve: AppMotion.standard,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _customOpen
                ? CustomPanel(
                    key: const ValueKey('custom'),
                    onBack: () => setState(() => _customOpen = false),
                  )
                : selection.arenaMode
                ? const ArenaPanel(key: ValueKey('arena'))
                : _SliderBody(
                    key: const ValueKey('slider'),
                    selection: selection,
                    shownTier: shownTier,
                    tints: tints,
                    onDrag: (t) => setState(() => _preview = t),
                    onCommit: (t) {
                      ref.read(modelSelectionProvider.notifier).setPreset(t);
                      setState(() => _preview = null);
                    },
                    onOpenCustom: () => setState(() => _customOpen = true),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Slider + tier labels + Custom row — the "presets" half of the card.
class _SliderBody extends StatelessWidget {
  const _SliderBody({
    super.key,
    required this.selection,
    required this.shownTier,
    required this.tints,
    required this.onDrag,
    required this.onCommit,
    required this.onOpenCustom,
  });

  final ModelSelection selection;
  final Tier shownTier;
  final List<int> tints;
  final ValueChanged<Tier> onDrag;
  final ValueChanged<Tier> onCommit;
  final VoidCallback onOpenCustom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so the card's 60%-viewport clamp never clips content.
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: StrengthSlider(
              value: shownTier.index.toDouble(),
              detentColors: [for (final v in tints) Color(v)],
              onChanged: (i) => onDrag(Tier.values[i]),
              onChangeEnd: (i) => onCommit(Tier.values[i]),
            ),
          ),
          // Tier labels — active one brightens.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in Tier.values)
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.fast,
                    style:
                        (t == shownTier
                                ? theme.textTheme.labelLarge
                                : theme.textTheme.labelSmall)!
                            .copyWith(
                              color: t == shownTier
                                  ? Color(tints[t.index])
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                    child: Text(t.label),
                  ),
              ],
            ),
          ),
          // No Spacer here — the Column is inside a SingleChildScrollView
          // (unbounded height), so it would throw at runtime.
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          InkWell(
            onTap: onOpenCustom,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Custom', style: theme.textTheme.titleSmall),
                  if (selection.customModelId != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '· custom model active',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
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
