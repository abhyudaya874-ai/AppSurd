import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/ai/model_catalog.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../accountability/roast_card.dart';
import '../verification/verdict_model.dart';
import 'arena_models.dart';

/// Pinned top bar — one circle per judge, filling ✓/~ /✗/DNF with latency.
class JuryBar extends StatelessWidget {
  const JuryBar({
    super.key,
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
          Builder(
            builder: (context) {
              final r = results.where((r) => r.model.id == m.id).firstOrNull;
              final isRunning = running.contains(m.id);
              final tint = tints.forId(m.provider.id);
              final (icon, fill) = switch (r) {
                null when isRunning => (null, 0.0),
                null => (null, 0.0),
                JudgeResult(verdict: null) => (-1, 1.0),
                JudgeResult(verdict: Verdict(kind: VerdictKind.pass)) => (
                  1,
                  1.0,
                ),
                JudgeResult(verdict: Verdict(kind: VerdictKind.partial)) => (
                  0,
                  1.0,
                ),
                _ => (-2, 1.0),
              };
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Column(
                  children: [
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
                              backgroundColor: tint.withValues(alpha: 0.15),
                            ),
                          ),
                          if (icon == 1)
                            Icon(Icons.check, size: 16, color: tint)
                          else if (icon == 0)
                            Text('~', style: TextStyle(color: tint))
                          else if (icon == -1)
                            Icon(
                              Icons.close,
                              size: 14,
                              color: theme.colorScheme.error,
                            )
                          else if (icon == -2)
                            Icon(
                              Icons.close,
                              size: 14,
                              color: theme.colorScheme.error,
                            )
                          else
                            SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tint.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r == null
                          ? (isRunning ? '…' : m.provider.label.substring(0, 1))
                          : (r.verdict == null ? 'DNF' : '${r.latencyMs}ms'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Swipeable judge cards — one per model, verdict chip + confidence +
/// latency + streamed summary; dissenters get the dashed border.
class JudgeCards extends StatelessWidget {
  const JudgeCards({
    super.key,
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
        JudgeCard(
          key: ValueKey(m.id),
          model: m,
          result: results.where((r) => r.model.id == m.id).firstOrNull,
          running: running.contains(m.id),
          dissent:
              outcome != null &&
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
    return PageView(
      controller: page,
      onPageChanged: onPage,
      children: [
        for (var i = 0; i < cards.length; i++)
          FadeSlideIn(
            index: i,
            stagger: const Duration(milliseconds: 90),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: cards[i],
            ),
          ),
      ],
    );
  }
}

class JudgeCard extends StatelessWidget {
  const JudgeCard({
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
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final tint = tints.forId(model.provider.id);
    final v = result?.verdict;
    final (vLabel, vColor) = v == null
        ? (result != null ? 'DNF' : '…', theme.colorScheme.onSurfaceVariant)
        : switch (v.kind) {
            VerdictKind.pass => ('pass', theme.colorScheme.primary),
            VerdictKind.partial => ('partial', theme.colorScheme.tertiary),
            VerdictKind.fail => ('fail', theme.colorScheme.error),
          };
    final card = AnimatedContainer(
      duration: AppMotion.base,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: dissent
            ? null // dashed overlay below carries the dissent outline
            : Border.all(color: tint.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: tint.withValues(alpha: 0.2),
                child: Text(
                  model.provider.label.substring(0, 1),
                  style: TextStyle(
                    fontSize: 10,
                    color: tint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  model.displayName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (dissent)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xxs),
                  child: Text(
                    'dissent',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: vColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: vColor),
                ),
                child: Text(
                  vLabel,
                  style: theme.textTheme.labelSmall?.copyWith(color: vColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: running && result == null
                ? const JudgeThinking()
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
    if (!dissent) return card;
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(color: theme.colorScheme.tertiary),
      child: card,
    );
  }
}

class JudgeThinking extends StatelessWidget {
  const JudgeThinking();
  @override
  Widget build(BuildContext context) => Text(
    'deliberating…',
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

/// Consensus meter + final verdict + strictest-judge roast/challenge.
class ConsensusSection extends StatelessWidget {
  const ConsensusSection({
    super.key,
    required this.outcome,
    required this.tints,
    required this.taskId,
  });

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ConsensusMeter(ratio: outcome.agreement, color: color),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unanimous ? 'Unanimous' : 'Split decision',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${(outcome.agreement * 100).round()}% agree · '
                  '${outcome.dissenters.length} dissent',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
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
      ],
    );
  }
}

/// Animated arc filling to the agreement ratio.
class ConsensusMeter extends StatefulWidget {
  const ConsensusMeter({super.key, required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  State<ConsensusMeter> createState() => ConsensusMeterState();
}

class ConsensusMeterState extends State<ConsensusMeter>
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
    final track = Theme.of(context).colorScheme.outline.withValues(alpha: 0.3);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: const Size.square(52),
        painter: MeterPainter(
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

class MeterPainter extends CustomPainter {
  const MeterPainter({
    required this.progress,
    required this.color,
    required this.track,
  });
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(MeterPainter old) => old.progress != progress;
}

class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
      ],
    );
  }
}

/// Dashed rounded-rect border — the dissent card's "I disagree" styling.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 4.0;
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rr);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) => old.color != color;
}
