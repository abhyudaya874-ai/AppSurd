import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/brand_icon.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/pressable.dart';
import '../model_picker/model_selection.dart';
import '../settings/settings_screen.dart';
import '../shell/app_shell.dart' show MenuAvatar;
import '../tasks/create_task_screen.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import '../verification/verdict_model.dart';
import 'arena_chat_state.dart';
import 'arena_models.dart';
import 'arena_service.dart';
import 'arena_state.dart';

/// The prompt Home seeds when the Arena pill is tapped with text — lands in
/// the Arena evidence composer, not a chat field.
final arenaSeedProvider = NotifierProvider<_SeedNotifier, String?>(
  _SeedNotifier.new,
);

class _SeedNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

/// Arena home — "Put a task on trial." Pick an open task, attach/paste its
/// proof, pick two judges, run. Pushes the side-by-side [TrialScreen].
class ArenaHomeScreen extends ConsumerStatefulWidget {
  const ArenaHomeScreen({super.key});

  @override
  ConsumerState<ArenaHomeScreen> createState() => _ArenaHomeState();
}

class _ArenaHomeState extends ConsumerState<ArenaHomeScreen> {
  final _evidenceCtrl = TextEditingController();
  String? _selectedTaskId;
  XFile? _photo;
  ArenaMode _mode = ArenaMode.sideBySide;
  final _lineup = <ModelSpec?>[null, null];

  @override
  void initState() {
    super.initState();
    final seed = ref.read(arenaSeedProvider);
    if (seed != null && seed.isNotEmpty) {
      _evidenceCtrl.text = seed;
      ref.read(arenaSeedProvider.notifier).set(null);
    }
    _evidenceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _evidenceCtrl.dispose();
    super.dispose();
  }

  /// Default A/B: the persisted arena lineup if valid, else the two best
  /// keyed curated models, else seed defaults (demo can still run).
  List<ModelSpec?> _defaultPair(Map<AiProvider, String> keys) {
    final lineup = ref.read(arenaLineupProvider);
    if (lineup.length >= 2) return [lineup[0], lineup[1]];
    final keyed = [
      for (final id in defaultLineup())
        ...kModelCatalog.where((m) => m.id == id),
    ];
    if (keyed.length >= 2) return [keyed[0], keyed[1]];
    return [kModelCatalog.firstOrNull, kModelCatalog.elementAtOrNull(1)];
  }

  void _runTrial(Task task) {
    final a = _lineup[0];
    final b = _lineup[1];
    final text = _evidenceCtrl.text.trim();
    if (a == null || b == null || (text.isEmpty && _photo == null)) return;

    // Evidence type from the input — same rules the Evidence sheet uses.
    final (type, payload) = switch (true) {
      _ when _photo != null => (EvidenceType.screenshot, _photo!.path),
      _ when text.contains('github.com') && text.contains('/commit/') => (
        EvidenceType.commit,
        text,
      ),
      _ when Uri.tryParse(text)?.hasScheme ?? false => (EvidenceType.url, text),
      _ => (EvidenceType.text, text),
    };
    final attempt = EvidenceAttempt(
      id: const Uuid().v4(),
      type: type,
      payload: payload,
      submittedAt: DateTime.now(),
    );
    final judges = _mode == ArenaMode.jury
        ? ref.read(arenaLineupProvider)
        : [a, b];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrialScreen(
          task: task,
          attempt: attempt,
          judges: judges,
          mode: _mode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks =
        (ref.watch(tasksProvider).value ?? const [])
            .where((t) => t.status != TaskStatus.done)
            .toList()
          ..sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    _selectedTaskId ??= tasks.isNotEmpty ? tasks.first.id : null;
    final keys = ref.watch(configuredKeysProvider).value ?? const {};
    _lineup[0] ??= _defaultPair(keys)[0];
    _lineup[1] ??= _defaultPair(keys)[1];
    final selectedTask = tasks.isEmpty
        ? null
        : tasks.firstWhere(
            (t) => t.id == _selectedTaskId,
            orElse: () => tasks.first,
          );

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Arena'),
          leading: const MenuAvatar(),
          actions: [
            IconButton(
              tooltip: 'Arena settings',
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: AnimatedPadding(
          padding: MediaQuery.viewInsetsOf(context),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Put a task on trial.',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: 'Fraunces',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Two models judge your proof. Compare their reasoning.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(height: 92, child: _taskCards(tasks, theme)),
                    const SizedBox(height: AppSpacing.sm),
                    _composer(theme, selectedTask),
                  ],
                ),
              ),
              _bottomBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal task cards — title, due chip, Demo badge; "+ New task" last.
  Widget _taskCards(List<Task> tasks, ThemeData theme) {
    if (tasks.isEmpty) {
      return Center(
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CreateTaskScreen(initialTitle: ''),
            ),
          ),
          icon: const Icon(Icons.add_task, size: 16),
          label: const Text('Create a task first'),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: tasks.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == tasks.length) {
          return _NewTaskCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CreateTaskScreen(initialTitle: ''),
              ),
            ),
          );
        }
        final t = tasks[i];
        final sel = t.id == _selectedTaskId;
        return Pressable(
          onTap: () => setState(() => _selectedTaskId = t.id),
          child: Container(
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sel
                  ? theme.colorScheme.primaryContainer.withValues(alpha: .5)
                  : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: .4),
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                Row(
                  children: [
                    if (t.isDemo)
                      Text(
                        'DEMO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontSize: 9,
                        ),
                      ),
                    const Spacer(),
                    Icon(
                      Icons.gavel_outlined,
                      size: 12,
                      color: sel
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Evidence composer card — paste text/link or attach a photo.
  Widget _composer(ThemeData theme, Task? task) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _evidenceCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: task == null
                  ? 'Paste proof, a link or a commit URL…'
                  : 'Paste proof for "${task.title}"…',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Attach photo',
                onPressed: () async {
                  final img = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1280,
                  );
                  if (img != null) setState(() => _photo = img);
                },
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: 'Take photo',
                onPressed: () async {
                  final img = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1280,
                  );
                  if (img != null) setState(() => _photo = img);
                },
                icon: Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_photo != null) ...[
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(_photo!.path),
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove photo',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _photo = null),
                  icon: const Icon(Icons.close, size: 14),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom bar: A/B model chips on their own line, then mode + send —
  /// never clips the 44dp send button at 360dp / 1.3x text scale.
  Widget _bottomBar(ThemeData theme) {
    final canRun =
        _lineup[0] != null &&
        _lineup[1] != null &&
        (_evidenceCtrl.text.trim().isNotEmpty || _photo != null) &&
        _selectedTaskId != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          4,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModelChip(
                    letter: 'A',
                    spec: _lineup[0],
                    onPick: (m) => setState(() => _lineup[0] = m),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModelChip(
                    letter: 'B',
                    spec: _lineup[1],
                    onPick: (m) => setState(() => _lineup[1] = m),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ModeMenu(
                  mode: _mode,
                  onPick: (m) => setState(() => _mode = m),
                ),
                const Spacer(),
                SizedBox.square(
                  dimension: 44,
                  child: Material(
                    color: canRun
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: canRun
                          ? () => _runTrial(
                              (ref.read(tasksProvider).value ?? []).firstWhere(
                                (t) => t.id == _selectedTaskId,
                              ),
                            )
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Icon(
                        Icons.gavel_rounded,
                        size: 20,
                        color: canRun
                            ? theme.colorScheme.surface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "+ New task" card — opens Create Task, result comes back on the list.
class _NewTaskCard extends StatelessWidget {
  const _NewTaskCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: .4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: theme.colorScheme.onSurfaceVariant),
            Text(
              'New task',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact mode dropdown — Side by Side / Battle / Jury.
class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.mode, required this.onPick});
  final ArenaMode mode;
  final ValueChanged<ArenaMode> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const labels = {
      ArenaMode.sideBySide: 'Side by Side',
      ArenaMode.battle: 'Battle',
      ArenaMode.jury: 'Jury 3–4',
    };
    return PopupMenuButton<ArenaMode>(
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final m in ArenaMode.values)
          PopupMenuItem(
            value: m,
            height: 36,
            child: Row(
              children: [
                if (m == mode)
                  const Icon(Icons.check, size: 14)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 6),
                Text(labels[m]!),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[mode]!, style: theme.textTheme.labelMedium),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// A/B model chip — curated task-scope list, brand icon, ellipsised name.
class _ModelChip extends StatelessWidget {
  const _ModelChip({
    required this.letter,
    required this.spec,
    required this.onPick,
  });
  final String letter;
  final ModelSpec? spec;
  final ValueChanged<ModelSpec> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: theme.colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _JudgePicker(onPick: onPick),
      ),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Row(
          children: [
            Text(
              letter,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            if (spec != null) BrandIcon(model: spec!, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                spec?.displayName ?? 'Pick model',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Judge picker sheet — CURATED task-scope catalog grouped by provider;
/// unkeyed rows stay locked with an "Add key" action.
class _JudgePicker extends ConsumerWidget {
  const _JudgePicker({required this.onPick});
  final ValueChanged<ModelSpec> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keys = ref.watch(configuredKeysProvider).value ?? const {};
    final models = ref.watch(curatedCatalogProvider).value ?? kModelCatalog;
    final groups = <AiProvider, List<ModelSpec>>{};
    for (final m in models) {
      groups.putIfAbsent(m.provider, () => []).add(m);
    }
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final p in groups.keys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text(
                p.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final m in groups[p]!)
              ListTile(
                dense: true,
                leading: BrandIcon(model: m, size: 18, showBadge: false),
                title: Text(m.displayName, maxLines: 1),
                trailing: keys.containsKey(p)
                    ? null
                    : TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                        child: const Text('Add key'),
                      ),
                onTap: keys.containsKey(p)
                    ? () {
                        onPick(m);
                        Navigator.pop(context);
                      }
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}

/// The side-by-side trial — fans the task's evidence out to every judge via
/// ArenaService, shows each verdict in its own card, and computes the
/// consensus in code (never a model).
class TrialScreen extends ConsumerStatefulWidget {
  const TrialScreen({
    super.key,
    required this.task,
    required this.attempt,
    required this.judges,
    required this.mode,
  });

  final Task task;
  final EvidenceAttempt attempt;
  final List<ModelSpec> judges;
  final ArenaMode mode;

  @override
  ConsumerState<TrialScreen> createState() => _TrialState();
}

class _TrialState extends ConsumerState<TrialScreen> {
  final _results = <String, JudgeResult>{};
  final _running = <String>{};
  ArenaOutcome? _outcome;
  final _sw = Stopwatch();
  bool _attemptAdded = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Registers the attempt on the task (so Accept can attach the verdict)
  /// and starts the concurrent judge fan-out.
  Future<void> _run() async {
    if (!_attemptAdded) {
      _attemptAdded = true;
      await ref
          .read(tasksProvider.notifier)
          .addAttempt(widget.task.id, widget.attempt);
    }
    setState(() {
      _results.clear();
      _running
        ..clear()
        ..addAll(widget.judges.map((m) => m.id));
      _outcome = null;
      _sw
        ..reset()
        ..start();
    });
    final strictness = ref.read(modelSelectionProvider).strictness;
    await for (final e
        in ref
            .read(arenaServiceProvider)
            .run(widget.task, widget.attempt, widget.judges, strictness)) {
      if (!mounted) return;
      setState(() {
        switch (e) {
          case JudgeDone(:final result):
            _results[result.model.id] = result;
            _running.remove(result.model.id);
          case ArenaDone(:final outcome):
            _outcome = outcome;
            _running.clear();
            _sw.stop();
          default:
            break;
        }
      });
    }
  }

  /// Applies the consensus verdict to the task (status + integrity delta +
  /// roast/challenge from the strictest judge) and persists the full arena
  /// record into the attempt's verdictJson.
  Future<void> _accept() async {
    final o = _outcome;
    if (o == null) return;
    final status = switch (o.consensus) {
      VerdictKind.pass => TaskStatus.done,
      VerdictKind.partial || VerdictKind.fail => TaskStatus.locked,
    };
    final delta = switch (o.consensus) {
      VerdictKind.pass => 10,
      VerdictKind.fail => -5,
      VerdictKind.partial => 0,
    };
    await ref
        .read(tasksProvider.notifier)
        .attachVerdict(
          widget.task.id,
          {
            ...o.consensusVerdict.toJson(),
            'arena': {
              'mode': widget.mode.name,
              'judges': [
                for (final j in o.results)
                  {
                    'modelId': j.model.id,
                    'provider': j.model.provider.name,
                    'verdict': j.verdict?.kind.name,
                    'confidence': j.verdict?.confidence,
                    'summary': j.verdict?.summary,
                    'latencyMs': j.latencyMs,
                    if (j.error != null) 'error': j.error,
                  },
              ],
              'consensus': o.consensus.name,
              'agreement': o.agreement,
              'dissenters': [for (final d in o.dissenters) d.model.id],
              'strictest': o.strictest?.model.id,
            },
          },
          status: status,
          integrityDelta: delta,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _outcome != null;
    final battle = widget.mode == ArenaMode.battle;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              done
                  ? 'Done in ${(_sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'
                  : 'Running…',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Re-run',
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.judges.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: RepaintBoundary(
                        child: FadeSlideIn(
                          index: i,
                          child: _JudgeCard(
                            index: i,
                            judge: widget.judges[i],
                            running: _running.contains(widget.judges[i].id),
                            result: _results[widget.judges[i].id],
                            hidden: battle && _outcome == null,
                            dissenting:
                                _outcome?.dissenters.any(
                                  (d) => d.model.id == widget.judges[i].id,
                                ) ??
                                false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _ConsensusBar(
            outcome: _outcome,
            judgeCount: widget.judges.length,
            onAccept: _accept,
            onRerun: _run,
          ),
        ],
      ),
    );
  }
}

/// One judge's card — brand mark (hidden in Battle), verdict chip, the
/// judge's checks/summary/confidence, DNF with retry on error.
class _JudgeCard extends StatelessWidget {
  const _JudgeCard({
    required this.index,
    required this.judge,
    required this.running,
    required this.result,
    required this.hidden,
    required this.dissenting,
  });
  final int index;
  final ModelSpec judge;
  final bool running;
  final JudgeResult? result;
  final bool hidden;
  final bool dissenting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = result?.verdict;
    final kind = v?.kind;
    final (label, color) = switch (kind) {
      VerdictKind.pass => ('PASS', theme.colorScheme.primary),
      VerdictKind.partial => ('PARTIAL', theme.colorScheme.tertiary),
      VerdictKind.fail => ('FAIL', theme.colorScheme.error),
      _ => ('', theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dissenting
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outline.withValues(alpha: .6),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hidden)
                Icon(
                  Icons.help_outline_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              else
                BrandIcon(model: judge, size: 14, showBadge: false),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hidden ? 'Model ${'ABCD'[index]}' : judge.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (running)
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (v != null)
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (dissenting)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'dissenting judge',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dashed,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result == null && running)
                    Text(
                      'Reading the proof…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (result != null && result!.error != null)
                    Text(
                      'DNF — ${result!.error}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (v != null) ...[
                    for (final c in v.checks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              c.ok
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.cancel_outlined,
                              size: 12,
                              color: c.ok
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                c.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      v.summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (v != null || result != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: v?.confidence ?? 0,
                        minHeight: 4,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${((v?.confidence ?? 0) * 100).round()}% · ${result!.latencyMs}ms',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinned consensus bar — aggregation from ArenaOutcome (code-side:
/// weighted vote, tie→stricter, strictness floor), with Accept / Re-run.
class _ConsensusBar extends StatelessWidget {
  const _ConsensusBar({
    required this.outcome,
    required this.judgeCount,
    required this.onAccept,
    required this.onRerun,
  });
  final ArenaOutcome? outcome;
  final int judgeCount;
  final VoidCallback onAccept;
  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = outcome;
    if (o == null) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Waiting on the judges…',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final (text, color) = switch (o.consensus) {
      VerdictKind.pass => ('VERIFIED', theme.colorScheme.primary),
      VerdictKind.partial => ('PARTIAL', theme.colorScheme.tertiary),
      VerdictKind.fail => ('FAIL', theme.colorScheme.error),
    };
    final agree = (o.agreement * judgeCount).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: .6),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: o.agreement,
                minHeight: 4,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              o.dissenters.isEmpty
                  ? '$agree/$judgeCount agree → $text'
                  : '$agree/$judgeCount agree → $text · '
                        'stricter judge wins',
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onRerun,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Re-run'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.gavel_rounded, size: 16),
                  label: const Text('Accept verdict'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
