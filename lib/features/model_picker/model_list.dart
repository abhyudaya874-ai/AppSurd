import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hive_ce/hive_ce.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/brand_icon.dart';
import '../../core/widgets/drawn_check.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/shimmer_box.dart';
import '../settings/settings_screen.dart';
import 'model_selection.dart';

/// Last 3 model picks — persisted, shown at the top of the list.
final _recentProvider = NotifierProvider<_Recent, List<String>>(_Recent.new);

class _Recent extends Notifier<List<String>> {
  static const _key = 'recent_models';
  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final box = await Hive.openBox('receipts_settings');
    final v = box.get(_key);
    if (v is List) state = v.cast<String>();
  }

  Future<void> push(String id) async {
    state = [id, ...state.where((x) => x != id)].take(3).toList();
    final box = await Hive.openBox('receipts_settings');
    await box.put(_key, state);
  }
}

/// The rule-11 model list: Recently Used → Recommended → All (grouped by
/// provider), strength bar + white dot, draw-on check, search. Sourced from
/// the live free catalog (seed catalog when /models is unreachable).
class ModelListPanel extends ConsumerStatefulWidget {
  const ModelListPanel({super.key});

  @override
  ConsumerState<ModelListPanel> createState() => _ModelListPanelState();
}

class _ModelListPanelState extends ConsumerState<ModelListPanel> {
  String _q = '';
  bool _seeMore = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = ref.watch(modelSelectionProvider);
    final keys = ref.watch(configuredKeysProvider).value ?? const {};
    final alive = ref.watch(aliveModelsProvider).value ?? const {};
    final live = ref.watch(liveCatalogProvider);
    final recentIds = ref.watch(_recentProvider);

    return live.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: ShimmerBox(height: 44, radius: 12),
            ),
        ]),
      ),
      error: (e, _) => ListTile(
        title: const Text('Could not load the live list'),
        subtitle: const Text('Using the built-in free catalog'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(liveCatalogProvider),
          child: const Text('Retry'),
        ),
      ),
      data: (catalog) {
        var models = catalog.where((m) =>
            alive[m.provider] == null || alive[m.provider]!.contains(m.id));
        if (_q.isNotEmpty) {
          final q = _q.toLowerCase();
          models = models.where((m) =>
              m.displayName.toLowerCase().contains(q) ||
              (m.brand ?? '').contains(q) ||
              m.id.toLowerCase().contains(q));
        }
        final list = models.toList();
        final recents = [
          for (final id in recentIds)
            ...list.where((m) => m.id == id),
        ];
        // Recommended: best-strength model per tier across free set.
        final recommended = [
          for (final tier in Tier.values)
            if (list.where((m) => m.tier == tier).isNotEmpty)
              list.where((m) => m.tier == tier)
                  .reduce((a, b) => a.strength >= b.strength ? a : b),
        ];
        // All-models per provider, long tail hidden behind "See more…".
        final byProvider = {
          for (final p in AiProvider.values)
            p: list.where((m) => m.provider == p).toList()
        };

        return Column(children: [
          // Compact search field.
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search models',
                prefixIcon: Icon(Icons.search, size: 16),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Flexible(
            child: RepaintBoundary(
              child: ListView(shrinkWrap: true, children: [
                if (recents.isNotEmpty && _q.isEmpty) ...[
                  _head('Recently Used', theme),
                  for (final m in recents)
                    _Row(m: m, selectedId: selection.customModelId,
                        hasKey: keys.containsKey(m.provider)),
                ],
                if (recommended.isNotEmpty && _q.isEmpty) ...[
                  _head('Recommended', theme),
                  for (final m in recommended)
                    _Row(m: m, selectedId: selection.customModelId,
                        hasKey: keys.containsKey(m.provider)),
                ],
                for (final p in AiProvider.values)
                  if ((byProvider[p] ?? []).isNotEmpty) ...[
                    _head(p.label, theme, provider: p,
                        locked: !keys.containsKey(p)),
                    for (final m in _seeMore || _q.isNotEmpty
                        ? byProvider[p]!
                        : byProvider[p]!.take(4).toList())
                      _Row(m: m, selectedId: selection.customModelId,
                          hasKey: keys.containsKey(p)),
                  ],
                if (!_seeMore && _q.isEmpty)
                  InkWell(
                    onTap: () => setState(() => _seeMore = true),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Center(
                        child: Text('See more…',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _head(String text, ThemeData theme,
      {AiProvider? provider, bool locked = false}) {
    return InkWell(
      onTap: locked
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const SettingsScreen()))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, 2),
        child: Row(children: [
          if (provider != null) ...[
            BrandIcon(
                model: ModelSpec(
                    id: provider.id,
                    provider: provider,
                    displayName: provider.label,
                    tier: Tier.swift,
                    strength: 0,
                    brand: null,
                    blurb: ''),
                size: 14,
                showBadge: false),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          if (locked)
            Icon(Icons.lock_outline,
                size: 13, color: theme.colorScheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// One model row: brand logo + name + variant labels + strength bar with
/// white dot; the selected row swaps the bar for a draw-on check.
class _Row extends ConsumerWidget {
  const _Row({required this.m, required this.selectedId, required this.hasKey});

  final ModelSpec m;
  final String? selectedId;
  final bool hasKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = selectedId == m.id;
    return Opacity(
      opacity: hasKey ? 1 : 0.45,
      child: Pressable(
        onTap: hasKey
            ? () {
                ref.read(modelSelectionProvider.notifier).setCustomModel(m.id);
                ref.read(_recentProvider.notifier).push(m.id);
              }
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen())),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 1),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            BrandIcon(model: m, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(m.displayName,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Row(children: [
                  if (m.supportsReasoning) _tag(theme, 'Reasoning'),
                  if (m.supportsVision) _tag(theme, 'Vision'),
                  if (m.contextK >= 128) _tag(theme, 'Long ctx'),
                ]),
              ]),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (selected)
              DrawnCheck(size: 14, color: theme.colorScheme.primary)
            else
              _StrengthBar(strength: m.strength),
          ]),
        ),
      ),
    );
  }

  Widget _tag(ThemeData theme, String label) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant)),
      );
}

/// ~70×6 gradient track + a white dot at the model's normalized strength.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});
  final double strength;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(70, 6),
        painter: _BarPainter(strength),
      );
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.strength);
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF232830));
    // green → amber → orange → violet gradient at the fill end
    final fill = Rect.fromLTWH(0, 0, size.width * strength, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, Radius.circular(size.height / 2)),
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0xFF4ADE80),
          Color(0xFFFBBF24),
          Color(0xFFFF8A5C),
          Color(0xFFB794F6),
        ]).createShader(Offset.zero & size),
    );
    canvas.drawCircle(
      Offset(size.width * strength.clamp(0.02, 0.98), size.height / 2),
      3.4,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.strength != strength;
}
