import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/model_catalog.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import '../verification/verdict_model.dart';
import 'arena_models.dart';
import 'arena_service.dart';
import 'arena_widgets.dart';

/// The jury screen: provider-tinted dots fill as judges return, judge cards
/// page underneath, a consensus meter animates to the agreement ratio, then
/// the final verdict + roast (from the strictest judge) are revealed.
class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({
    super.key,
    required this.taskId,
    required this.attemptId,
    required this.lineup,
    required this.strictness,
  });

  final String taskId;
  final String attemptId;
  final List<ModelSpec> lineup;
  final Strictness strictness;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  final _results = <JudgeResult>[];
  final _running = <String>{};
  ArenaOutcome? _outcome;
  late final ConfettiController _confetti;
  final _page = PageController();
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _confetti.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final task = ref.read(taskByIdProvider(widget.taskId));
    if (task == null) return;
    final attempt = task.attempts
        .where((a) => a.id == widget.attemptId)
        .firstOrNull;
    if (attempt == null) return;

    await for (final e
        in ref
            .read(arenaServiceProvider)
            .run(task, attempt, widget.lineup, widget.strictness)) {
      if (!mounted) return;
      switch (e) {
        case JudgeStarted():
          setState(() => _running.add(e.model.id));
        case JudgeDone():
          setState(() {
            _running.remove(e.result.model.id);
            _results.add(e.result);
          });
        case ArenaDone():
          setState(() => _outcome = e.outcome);
          await _apply(e.outcome);
      }
    }
  }

  Future<void> _apply(ArenaOutcome o) async {
    final status = o.consensus == VerdictKind.pass
        ? TaskStatus.done
        : TaskStatus.locked;
    final delta = switch (o.consensus) {
      VerdictKind.pass => 10,
      VerdictKind.fail => -5,
      VerdictKind.partial => 0,
    };
    await ref
        .read(tasksProvider.notifier)
        .attachVerdict(
          widget.taskId,
          o.consensusVerdict.toJson(),
          status: status,
          integrityDelta: delta,
        );
    if (o.consensus == VerdictKind.pass) {
      _confetti.play();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final o = _outcome;
    return Scaffold(
      appBar: AppBar(title: Text('Arena · ${widget.lineup.length} judges')),
      body: Stack(
        children: [
          ConstrainedContent(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                JuryBar(
                  lineup: widget.lineup,
                  results: _results,
                  running: _running,
                  tints: tints,
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: JudgeCards(
                    lineup: widget.lineup,
                    results: _results,
                    running: _running,
                    outcome: o,
                    page: _page,
                    onPage: (i) => setState(() => _pageIndex = i),
                  ),
                ),
                if (widget.lineup.length > 1)
                  PageDots(count: widget.lineup.length, index: _pageIndex),
                const SizedBox(height: AppSpacing.sm),
                if (o != null)
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: ConsensusSection(
                      outcome: o,
                      tints: tints,
                      taskId: widget.taskId,
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              gravity: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}
