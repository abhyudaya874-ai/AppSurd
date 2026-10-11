import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/model_catalog.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../accountability/roast_card.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import '../verification/verdict_model.dart';
import 'arena_models.dart';
import 'arena_service.dart';

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
    _confetti =
        ConfettiController(duration: const Duration(milliseconds: 1200));
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
    final attempt =
        task.attempts.where((a) => a.id == widget.attemptId).firstOrNull;
    if (attempt == null) return;

    await for (final e in ref.read(arenaServiceProvider).run(
        task, attempt, widget.lineup, widget.strictness)) {
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
    await ref.read(tasksProvider.notifier).attachVerdict(
        widget.taskId, o.consensusVerdict.toJson(),
        status: status, integrityDelta: delta);
    if (o.consensus == VerdictKind.pass) {
      _confetti.play();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints =
        theme.extension<ProviderTints>() ?? const ProviderTints();
    final o = _outcome;
    return Scaffold(
      appBar: AppBar(title: Text('Arena · ${widget.lineup.length} judges')),
      body: Stack(children: [
        ConstrainedContent(
          child: Column(children: [
            const SizedBox(height: AppSpacing.sm),
            _JuryBar(
                lineup: widget.lineup,
                results: _results,
                running: _running,
                tints: tints),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _JudgeCards(
                lineup: widget.lineup,
                results: _results,
                running: _running,
                outcome: o,
                page: _page,
                onPage: (i) => setState(() => _pageIndex = i),
              ),
            ),
            if (widget.lineup.length > 1)
              _PageDots(
                  count: widget.lineup.length, index: _pageIndex),
            const SizedBox(height: AppSpacing.sm),
            if (o != null)
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _ConsensusSection(
                    outcome: o, tints: tints, taskId: widget.taskId),
              ),
          ]),
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
      ]),
    );
  }
}

/// Pinned top bar — one circle per judge, filling ✓/~ /✗/DNF with latency.
class _JuryBar extends StatelessWidget {
  const _JuryBar({
    required this.lineup,
    required this.results,
    required this.running,
    required this.tints,
  });

  final List<ModelSpec> lineup;
  final List<JudgeResult> results;
  final Set<String> running;
  final ProviderTints tints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final m in lineup)
          Builder(builder: (context) {
            final r =
                results.where((r) => r.model.id == m.id).firstOrNull;
            final isRunning = running.contains(m.id);
            final tint = tints.forId(m.provider.id);
            final (icon, fill) = switch (r) {
              null when isRunning => (null, 0.0),
              null => (null, 0.0),
              JudgeResult(verdict: null) => (-1, 1.0),
              JudgeResult(verdict: Verdict(kind: VerdictKind.pass)) =>
                (1, 1.0),
              JudgeResult(verdict: Verdict(kind: VerdictKind.partial)) =>
                (0, 1.0),
              _ => (-2, 1.0),
            };
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fill),
                  duration: AppMotion.slow,
                  curve: AppMotion.standard,
                  builder: (context, t, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 34,
                        child: CircularProgressIndicator(
                          value: t,
                          strokeWidth: 3,
                          color: tint,
                          backgroundColor:
                              tint.withValues(alpha: 0.15),
                        ),
                      ),
                      if (icon == 1)
                        Icon(Icons.check, size: 16, color: tint)
                      else if (icon == 0)
                        Text('~', style: TextStyle(color: tint))
                      else if (icon == -1)
                        Icon(Icons.close,
                            size: 14, color: theme.colorScheme.error)
                      else if (icon == -2)
                        Icon(Icons.close,
                            size: 14, color: theme.colorScheme.error)
                      else
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tint.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r == null
                      ? (isRunning ? '…' : m.provider.label.substring(0, 1))
                      : (r.verdict == null
                          ? 'DNF'
                          : '${r.latencyMs}ms'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
              ]),
            );
          }),
      ],
    );
  }
}

/// Swipeable judge cards — one per model, verdict chip + confidence +
/// latency + streamed summary; dissenters get the dashed border.
class _JudgeCards extends StatelessWidget {
  const _JudgeCards({
    required this.lineup,
    required this.results,
    required this.running,
    required this.outcome,
    required this.page,
    required this.onPage,
  });

  final List<ModelSpec> lineup;
  final List<JudgeResult> results;
  final Set<String> running;
  final ArenaOutcome? outcome;
  final PageController page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final cards = [
      for (final m in lineup)
        _JudgeCard(
          key: ValueKey(m.id),
          model: m,
          result:
              results.where((r) => r.model.id == m.id).firstOrNull,
          running: running.contains(m.id),
          dissent: outcome != null &&
              (outcome!.dissenters.any((d) => d.model.id == m.id)),
        ),
    ];
    if (wide) {
      return GridView.count(
        crossAxisCount: cards.length.clamp(2, 4),
        childAspectRatio: 2.4,
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: cards,
      );
    }
    return PageView(controller: page, onPageChanged: onPage, children: [
      for (var i = 0; i < cards.length; i++)
        FadeSlideIn(index: i, stagger: const Duration(milliseconds: 90),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: cards[i],
            )),
    ]);
  }
}

class _JudgeCard extends StatelessWidget {
  const _JudgeCard({
    super.key,
    required this.model,
    required this.result,
    required this.running,
    required this.dissent,
  });

  final ModelSpec model;
  final JudgeResult? result;
  final bool running;
  final bool dissent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints =
        theme.extension<ProviderTints>() ?? const ProviderTints();
    final tint = tints.forId(model.provider.id);
    final v = result?.verdict;
    final (vLabel, vColor) = v == null
        ? (result != null ? 'DNF' : '…', theme.colorScheme.onSurfaceVariant)
        : switch (v.kind) {
            VerdictKind.pass => ('pass', theme.colorScheme.primary),
            VerdictKind.partial => ('partial', theme.colorScheme.tertiary),
            VerdictKind.fail => ('fail', theme.colorScheme.error),
          };
    return AnimatedContainer(
      duration: AppMotion.base,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dissent
              ? theme.colorScheme.tertiary
              : tint.withValues(alpha: 0.5),
          // Dashed dissent look: simulated with a wider, warning-tinted
          // border + tag (dashed borders need a painter; see polish).
          width: dissent ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: tint.withValues(alpha: 0.2),
            child: Text(model.provider.label.substring(0, 1),
                style: TextStyle(
                    fontSize: 10, color: tint, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
              child: Text(model.displayName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis)),
          if (dissent)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: Text('dissent',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: 2),
            decoration: BoxDecoration(
              color: vColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: vColor),
            ),
            child: Text(vLabel,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: vColor)),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: running && result == null
              ? const _JudgeThinking()
              : Text(
                  result?.error != null
                      ? 'DNF — ${result!.error}'
                      : (v?.summary ?? ''),
                  style: theme.textTheme.bodySmall,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (result != null && v != null)
          Text(
            '${(v.confidence * 100).round()}% · ${result!.latencyMs}ms',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
      ]),
    );
  }
}

class _JudgeThinking extends StatelessWidget {
  const _JudgeThinking();
  @override
  Widget build(BuildContext context) => Text('deliberating…',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

/// Consensus meter + final verdict + strictest-judge roast/challenge.
class _ConsensusSection extends StatelessWidget {
  const _ConsensusSection(
      {required this.outcome, required this.tints, required this.taskId});

  final ArenaOutcome outcome;
  final ProviderTints tints;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = outcome.consensusVerdict;
    final (label, color) = switch (outcome.consensus) {
      VerdictKind.pass => ('Verified', theme.colorScheme.primary),
      VerdictKind.partial => ('Not quite', theme.colorScheme.tertiary),
      VerdictKind.fail => ('Rejected', theme.colorScheme.error),
    };
    final unanimous = outcome.agreement >= 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _ConsensusMeter(ratio: outcome.agreement, color: color),
        const SizedBox(width: AppSpacing.md),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(unanimous ? 'Unanimous' : 'Split decision',
              style: theme.textTheme.titleMedium),
          Text(
            '${(outcome.agreement * 100).round()}% agree · '
            '${outcome.dissenters.length} dissent',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color),
          ),
          child: Text(label,
              style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ),
      ]),
      const SizedBox(height: AppSpacing.sm),
      Text(v.summary, style: theme.textTheme.bodyMedium),
      if (v.roast != null && outcome.consensus != VerdictKind.pass)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: RoastCard(
            roast:
                'Roast by ${outcome.strictest?.model.displayName ?? 'the jury'}: ${v.roast}',
            fallback: false,
            challenge: v.challenge,
            taskId: taskId,
          ),
        ),
      const SizedBox(height: AppSpacing.lg),
    ]);
  }
}

/// Animated arc filling to the agreement ratio.
class _ConsensusMeter extends StatefulWidget {
  const _ConsensusMeter({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  State<_ConsensusMeter> createState() => _ConsensusMeterState();
}

class _ConsensusMeterState extends State<_ConsensusMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: AppMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track =
        Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: const Size.square(52),
        painter: _MeterPainter(
          progress: Curves.easeOutCubic.transform(_c.value) * widget.ratio,
          color: widget.color,
          track: track,
        ),
        child: SizedBox.square(
          dimension: 52,
          child: Center(
            child: Text(
              '${(widget.ratio * _c.value * 100).round()}%',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter(
      {required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2,
        2 * pi * progress, false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.progress != progress;
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: AppMotion.fast,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == index ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == index
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ]);
  }
}
