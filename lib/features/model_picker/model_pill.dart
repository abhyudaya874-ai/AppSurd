import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/model_catalog.dart';
import '../../core/widgets/brand_icon.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import 'model_picker_overlay.dart';
import 'model_selection.dart';
import 'resolved_model.dart';

/// The signature pill: a 40px rounded chip in the composer showing the routed
/// model (provider glyph + name + preset + strength dots + chevron). Tapping
/// morphs it into the floating picker card via [ModelPickerOverlay].
class ModelPill extends ConsumerStatefulWidget {
  const ModelPill({super.key});

  @override
  ConsumerState<ModelPill> createState() => ModelPillState();
}

class ModelPillState extends ConsumerState<ModelPill>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  OverlayEntry? _entry;
  late final AnimationController _morph;

  bool get isOpen => _entry != null;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(vsync: this, duration: AppMotion.base);
  }

  @override
  void dispose() {
    _morph.dispose();
    _entry?.remove();
    super.dispose();
  }

  void open() {
    if (_entry != null) return;
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    _entry = OverlayEntry(
      builder: (context) => ModelPickerOverlay(
        link: _link,
        morph: _morph,
        anchorRect: anchor,
        onDismiss: close,
      ),
    );
    Overlay.of(context).insert(_entry!);
    _morph.forward(from: 0);
    setState(() {});
  }

  Future<void> close() async {
    if (_entry == null) return;
    await _morph.reverse();
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final selection = ref.watch(modelSelectionProvider);
    final model = ref.watch(resolvedModelProvider);
    final tint = model != null
        ? tints.forId(model.provider.id)
        : theme.colorScheme.onSurfaceVariant;
    final arena = selection.arenaMode;
    final lineupSpecs = [
      for (final id in selection.arenaLineup)
        ...kModelCatalog.where((m) => m.id == id),
    ];

    return CompositedTransformTarget(
      link: _link,
      child: PressableInk(
        onTap: open,
        child: AnimatedOpacity(
          opacity: isOpen ? 0.0 : 1.0, // the card grows out of the pill
          duration: AppMotion.fast,
          child: AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.7,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              // Cap the pill so it ellipsizes inside tight rows (composer).
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (arena)
                    _AvatarStack(models: lineupSpecs, tints: tints)
                  else ...[
                    model == null
                        ? _ProviderGlyph(tint: tint, letter: '?', locked: true)
                        : _DotMatrixGlyph(
                            tierIndex: selection.preset.index,
                            tint: tint,
                          ),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: AppMotion.fast,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text.rich(
                        key: ValueKey(
                          arena
                              ? 'arena-${selection.arenaLineup.length}'
                              : '${model?.id}-${selection.preset.name}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        TextSpan(
                          children: [
                            TextSpan(
                              text: arena
                                  ? 'Arena · ${lineupSpecs.length} models'
                                  : (model?.displayName ?? 'No model'),
                              style: theme.textTheme.labelLarge,
                            ),
                            TextSpan(
                              text: arena
                                  ? '  ${selection.strictness.name}'
                                  : '  ${selection.preset.label}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal ink-well pressable (the Pressable scale wrapper is applied at the
/// row level — here we just want the tap).
class PressableInk extends StatelessWidget {
  const PressableInk({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: child);
  }
}

/// Small tinted circle with the provider's initial — the "glyph" on the pill.
class _ProviderGlyph extends StatelessWidget {
  const _ProviderGlyph({
    required this.tint,
    required this.letter,
    required this.locked,
  });

  final Color tint;
  final String letter;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.2),
        border: Border.all(color: tint, width: 1.2),
      ),
      alignment: Alignment.center,
      child: locked
          ? Icon(Icons.lock_outline, size: 11, color: tint)
          : Text(
              letter,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: tint, fontWeight: FontWeight.w700),
            ),
    );
  }
}

/// 3×3 dot-matrix glyph — more dots lit = stronger tier (Swift 2, Balanced 4,
/// Smart 6, Deep 9). Dots light up one by one with a short stagger.
class _DotMatrixGlyph extends StatelessWidget {
  const _DotMatrixGlyph({required this.tierIndex, required this.tint});
  final int tierIndex;
  final Color tint;

  static const _lit = [2, 4, 6, 9]; // dots lit per tier

  @override
  Widget build(BuildContext context) {
    final lit = _lit[tierIndex.clamp(0, 3)];
    return SizedBox(
      width: 20,
      height: 20,
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (var i = 0; i < 9; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: i < lit ? 1 : 0),
              duration: Duration(milliseconds: 140 + (i * 40)),
              curve: Curves.easeOutBack,
              builder: (context, v, _) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: 0.25 + 0.75 * v),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Overlapping provider glyphs — the arena lineup at a glance.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.models, required this.tints});
  final List<ModelSpec> models;
  final ProviderTints tints;

  @override
  Widget build(BuildContext context) {
    const size = 20.0, overlap = 7.0;
    final n = models.length;
    return SizedBox(
      width: size + (n > 0 ? (n - 1) * (size - overlap) : 0),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: tints.forId(models[i].provider.id),
                    width: 1.2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(3),
                child: BrandIcon(model: models[i], size: 14, showBadge: false),
              ),
            ),
          if (n == 0)
            Icon(
              Icons.groups_outlined,
              size: size,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}
