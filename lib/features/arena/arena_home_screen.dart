import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/brand_icon.dart';
import '../shell/app_shell.dart' show MenuAvatar;
import '../model_picker/model_selection.dart';
import '../settings/settings_screen.dart';
import 'arena_chat_state.dart';

/// Optional seed text — Home's Arena mode and Ask's "Compare" set it so the
/// arena composer opens prefilled (cleared on first read).
final arenaSeedProvider = NotifierProvider<_Seed, String>(_Seed.new);

class _Seed extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

/// First-class Arena destination: "which model proves it better?"
/// Side-by-Side (names shown), Battle (blind until you vote), Jury (the
/// verification lineup). Two models answer every prompt concurrently.
class ArenaHomeScreen extends ConsumerStatefulWidget {
  const ArenaHomeScreen({super.key});

  @override
  ConsumerState<ArenaHomeScreen> createState() => _ArenaHomeScreenState();
}

class _ArenaHomeScreenState extends ConsumerState<ArenaHomeScreen> {
  final _ctrl = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(arenaChatProvider.notifier).send(text);
    _ctrl.clear();
    setState(() {});
  }

  /// Anchored model dropdown: full catalog grouped by provider, live models
  /// first; unkeyed providers are disabled rows that jump to Settings.
  Future<void> _pickModel(bool isA) async {
    final theme = Theme.of(context);
    final catalog = await ref.read(liveCatalogProvider.future);
    final keys = ref.read(configuredKeysProvider).value ?? const {};
    if (!mounted) return;
    final picked = await showModalBottomSheet<ModelSpec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ModelPickerSheet(catalog: catalog, keys: keys),
    );
    if (picked == null) return;
    final n = ref.read(arenaChatProvider.notifier);
    if (isA) {
      n.setSpecA(picked);
    } else {
      n.setSpecB(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = ref.watch(arenaChatProvider);
    // Home's Arena segment / Ask's Compare seed the composer once.
    final seed = ref.watch(arenaSeedProvider);
    if (!_seeded && seed.isNotEmpty) {
      _seeded = true;
      _ctrl.text = seed;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(arenaSeedProvider.notifier).set(''),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Header — menu + title + lineup shortcut.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  const MenuAvatar(size: 34),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Arena', style: theme.textTheme.headlineLarge),
                  const Spacer(),
                ],
              ),
            ),

            // Rounds / empty state.
            Expanded(
              child: chat.rounds.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Which model\nproves it better?',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Two models answer. You pick the receipt.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      itemCount: chat.rounds.length,
                      itemBuilder: (context, i) =>
                          _Round(round: chat.rounds[i], index: i),
                    ),
            ),

            // Composer card.
            _composer(theme, chat),
          ],
        ),
      ),
    );
  }

  /// Bottom-pinned composer: field + bottom row [mode · A · B · send].
  /// Jury mode swaps the dropdowns for the verification-jury switch.
  Widget _composer(ThemeData theme, ArenaChatState chat) {
    final jury = ref.watch(modelSelectionProvider);
    return AnimatedPadding(
      duration: AppMotion.of(context, AppMotion.base),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ask anything…',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  _modeMenu(theme, chat.mode),
                  const SizedBox(width: AppSpacing.xs),
                  if (chat.mode == ArenaMode.jury)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.balance_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Verification jury · ${jury.arenaLineup.length} models',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Switch(
                            value: jury.arenaMode,
                            onChanged: (v) => ref
                                .read(modelSelectionProvider.notifier)
                                .setArenaMode(v),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    _modelChip(theme, chat.specA, () => _pickModel(true)),
                    const SizedBox(width: AppSpacing.xs),
                    _modelChip(theme, chat.specB, () => _pickModel(false)),
                    const Spacer(),
                  ],
                  _sendButton(theme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mode dropdown — Side by Side / Battle / Jury.
  Widget _modeMenu(ThemeData theme, ArenaMode mode) {
    const labels = {
      ArenaMode.sideBySide: 'Side by Side',
      ArenaMode.battle: 'Battle',
      ArenaMode.jury: 'Jury',
    };
    return MenuAnchor(
      builder: (context, controller, child) => TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[mode]!, style: theme.textTheme.labelLarge),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
      menuChildren: [
        for (final m in ArenaMode.values)
          MenuItemButton(
            trailingIcon: m == mode ? const Icon(Icons.check, size: 16) : null,
            onPressed: () => ref.read(arenaChatProvider.notifier).setMode(m),
            child: Text(labels[m]!),
          ),
      ],
    );
  }

  /// Small model chip: brand icon + truncated name + chevron.
  Widget _modelChip(ThemeData theme, ModelSpec? spec, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spec != null)
              BrandIcon(model: spec, size: 14, showBadge: false),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                spec?.displayName ?? 'Pick',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 14),
          ],
        ),
      ),
    );
  }

  /// Square outlined send — enabled only with text + two models.
  Widget _sendButton(ThemeData theme) {
    final chat = ref.watch(arenaChatProvider);
    final ready =
        _ctrl.text.trim().isNotEmpty &&
        chat.specA != null &&
        chat.specB != null;
    return InkWell(
      onTap: ready ? _send : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.fast),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: ready ? theme.colorScheme.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ready
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outline,
          ),
        ),
        child: Icon(
          Icons.arrow_upward_rounded,
          size: 20,
          color: ready
              ? theme.colorScheme.surface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One prompt + its two answers. User bubble on the right, then the cards —
/// side-by-side on ≥600dp, stacked on phones.
class _Round extends ConsumerWidget {
  const _Round({required this.round, required this.index});
  final ArenaRound round;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width >= 600;
    final cards = [
      for (var i = 0; i < round.cards.length; i++)
        _ResponseCard(round: round, card: round.cards[i], index: index, ci: i),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(round.prompt, style: theme.textTheme.bodyMedium),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 8),
                Expanded(child: cards[1]),
              ],
            )
          else ...[
            cards[0],
            const SizedBox(height: 8),
            cards[1],
          ],
          const SizedBox(height: AppSpacing.xs),
          _VoteRow(round: round, index: index),
        ],
      ),
    );
  }
}

/// A single model's answer card: status header (dot/spinner, brand icon,
/// name, actions), markdown body, latency footer.
class _ResponseCard extends ConsumerWidget {
  const _ResponseCard({
    required this.round,
    required this.card,
    required this.index,
    required this.ci,
  });
  final ArenaRound round;
  final ArenaCard card;
  final int index;
  final int ci;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final n = ref.read(arenaChatProvider.notifier);
    final loading = card.status == CardStatus.streaming;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
            child: Row(
              children: [
                // Status dot: spins while streaming, dim when queued.
                SizedBox(
                  width: 14,
                  height: 14,
                  child: loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.circle,
                          size: 8,
                          color: card.status == CardStatus.error
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                ),
                const SizedBox(width: 6),
                BrandIcon(model: card.spec, size: 16, showBadge: false),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card.shownName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                _mini(
                  Icons.refresh_rounded,
                  'Regenerate',
                  () => n.retry(index, ci),
                ),
                _mini(
                  Icons.copy_rounded,
                  'Copy',
                  () => Clipboard.setData(ClipboardData(text: card.text)),
                ),
                _mini(
                  Icons.open_in_full_rounded,
                  'Expand',
                  () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      builder: (_, sc) => SingleChildScrollView(
                        controller: sc,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: MarkdownBody(data: card.text),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: card.status == CardStatus.error
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.error ?? 'Failed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => n.retry(index, ci),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : MarkdownBody(
                    data: loading && card.text.isEmpty
                        ? '_thinking…_'
                        : card.text,
                    styleSheet: MarkdownStyleSheet(
                      p: theme.textTheme.bodySmall,
                    ),
                  ),
          ),
          if (card.ms != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '${card.ms} ms',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mini(IconData icon, String tip, VoidCallback onTap) => IconButton(
    icon: Icon(icon, size: 15),
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );
}

/// Vote buttons under a round — one vote, then locked (Battle reveals).
class _VoteRow extends ConsumerWidget {
  const _VoteRow({required this.round, required this.index});
  final ArenaRound round;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(arenaChatProvider.notifier);
    const labels = ['A better', 'Tie', 'B better'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var v = 0; v < 3; v++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(labels[v]),
              selected: round.vote == v,
              visualDensity: VisualDensity.compact,
              onSelected: round.vote >= 0 ? null : (_) => n.vote(index, v),
            ),
          ),
      ],
    );
  }
}

/// Bottom-sheet model picker: search + provider-grouped catalog; unkeyed
/// providers render disabled rows that push Settings.
class _ModelPickerSheet extends ConsumerStatefulWidget {
  const _ModelPickerSheet({required this.catalog, required this.keys});
  final List<ModelSpec> catalog;
  final Map<AiProvider, dynamic> keys;

  @override
  ConsumerState<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<_ModelPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var models = widget.catalog;
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      models = models
          .where((m) => m.displayName.toLowerCase().contains(q))
          .toList();
    }
    final byProvider = {
      for (final p in AiProvider.values)
        p: models.where((m) => m.provider == p).toList(),
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: 'Search models',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final p in AiProvider.values)
                if (byProvider[p]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: 2,
                    ),
                    child: Text(
                      p.label + (widget.keys[p] == null ? ' · add a key' : ''),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final m in byProvider[p]!)
                    ListTile(
                      dense: true,
                      enabled: widget.keys[p] != null,
                      leading: BrandIcon(model: m, size: 18, showBadge: false),
                      title: Text(
                        m.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.keys[p] == null
                          ? Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : null,
                      onTap: widget.keys[p] == null
                          ? () {
                              Navigator.pop(context);
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            }
                          : () => Navigator.pop(context, m),
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
