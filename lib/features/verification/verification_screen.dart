import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/ai_failure.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/drawn_check.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../accountability/roast_card.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import 'verification_service.dart';
import 'verdict_model.dart';

/// The Perplexity-style verification screen: animated step list, a strip of
/// sources the app fetched itself, the verdict with citations, and the roast /
/// challenge card on weak evidence.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen(
      {super.key, required this.taskId, required this.attemptId});

  final String taskId;
  final String attemptId;

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  // ---- pipeline state ----
  final _stepStates = <VerifyStep, VerifyStepState>{};
  List<SourceInfo> _sources = const [];
  Verdict? _verdict;
  String? _usedByLabel;
  String? _reroutedLabel;
  String? _visionSwapLabel;
  AiFailure? _failure;
  bool _roastFallback = false;

  late final ConfettiController _confetti;
  final _sourceKeys = <int, GlobalKey>{};
  final _stripScroll = ScrollController();

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
    _stripScroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final task = ref.read(taskByIdProvider(widget.taskId));
    if (task == null) return;
    final attempt =
        task.attempts.where((a) => a.id == widget.attemptId).firstOrNull;
    if (attempt == null) return;

    await for (final event
        in ref.read(verifierServiceProvider).verify(task, attempt)) {
      if (!mounted) return;
      switch (event) {
        case StepEvent():
          setState(() => _stepStates[event.step] = event.state);
        case SourcesEvent():
          setState(() => _sources = event.sources);
        case VerdictReadyEvent():
          _verdict = event.verdict;
          _roastFallback = event.roastIsFallback;
          _usedByLabel = event.usedBy != null
              ? '${event.usedBy!.provider.label} · ${event.usedBy!.displayName}'
              : 'local rules · demo verdict';
          _reroutedLabel = event.reroutedFrom != null
              ? 'rerouted from ${event.reroutedFrom!.label}'
              : null;
          _visionSwapLabel = event.visionSwappedTo != null
              ? 'Switched to ${event.visionSwappedTo!.displayName} to read your screenshot'
              : null;
          await _applyVerdict(event);
          setState(() {});
        case VerifyFailedEvent():
          setState(() => _failure = event.failure);
      }
    }
  }

  /// Applies the verdict to the task store — pass completes, partial/fail
  /// locks the task behind its challenge.
  Future<void> _applyVerdict(VerdictReadyEvent e) async {
    final status = switch (e.verdict.kind) {
      VerdictKind.pass => TaskStatus.done,
      VerdictKind.partial => TaskStatus.locked,
      VerdictKind.fail => TaskStatus.locked,
    };
    final delta = switch (e.verdict.kind) {
      VerdictKind.pass => 10,
      VerdictKind.fail => -5,
      VerdictKind.partial => 0,
    };
    await ref.read(tasksProvider.notifier).attachVerdict(
        widget.taskId, e.verdict.toJson(),
        status: status, integrityDelta: delta);
    if (e.verdict.kind == VerdictKind.pass) {
      _confetti.play();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  /// Pulses the i-th source card when a [n] citation pill is tapped.
  void _pulseSource(int index) {
    final key = _sourceKeys[index];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: AppMotion.base, curve: AppMotion.standard);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Verifying')),
      body: Stack(
        children: [
          _VerdictShake(
            verdict: _verdict?.kind,
            child: ConstrainedContent(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _StepList(states: _stepStates),
                const SizedBox(height: AppSpacing.md),
                if (_sources.isNotEmpty) ...[
                  Text('Sources', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      controller: _stripScroll,
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _sources.length; i++)
                          FadeSlideIn(
                            index: i,
                            stagger: const Duration(milliseconds: 90),
                            child: _SourceCard(
                              key: _sourceKeys.putIfAbsent(
                                  i, () => GlobalKey()),
                              source: _sources[i],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_failure != null)
                  _FailureCard(
                    failure: _failure!,
                    onRetry: () => setState(() {
                      _failure = null;
                      _stepStates.clear();
                      _sources = const [];
                      _verdict = null;
                      _run();
                    }),
                  ),
                if (_verdict != null)
                  _VerdictSection(
                    verdict: _verdict!,
                    usedBy: _usedByLabel,
                    rerouted: _reroutedLabel,
                    visionSwap: _visionSwapLabel,
                    roastIsFallback: _roastFallback,
                    onCitationTap: _pulseSource,
                    taskId: widget.taskId,
                  ),
              ],
            ),
          ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              gravity: 0.35,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.tertiary,
                theme.colorScheme.error,
                (theme.extension<ProviderTints>() ?? const ProviderTints()).groq,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four pipeline steps with spinner → drawn-check transitions.
class _StepList extends StatelessWidget {
  const _StepList({required this.states});
  final Map<VerifyStep, VerifyStepState> states;

  static const _labels = {
    VerifyStep.reading: 'Reading your evidence',
    VerifyStep.fetching: 'Fetching sources',
    VerifyStep.crossChecking: 'Cross-checking against the task',
    VerifyStep.writing: 'Writing verdict',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final step in VerifyStep.values)
          AnimatedContainer(
            duration: AppMotion.fast,
            padding:
                const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 2),
            child: Row(children: [
              SizedBox(
                width: 22,
                height: 22,
                child: switch (states[step]) {
                  VerifyStepState.done => DrawnCheck(
                      color: theme.colorScheme.primary,
                    ),
                  VerifyStepState.started => const Padding(
                      padding: EdgeInsets.all(2),
                      child:
                          CircularProgressIndicator(strokeWidth: 2)),
                  _ => Icon(Icons.circle_outlined,
                      size: 18,
                      color: theme.colorScheme.outline),
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: switch (states[step]) {
                    VerifyStepState.done => theme.colorScheme.onSurface,
                    VerifyStepState.started => theme.colorScheme.onSurface,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
                ),
                child: Text(_labels[step]!),
              ),
            ]),
          ),
      ],
    );
  }
}

/// One source card — favicon, domain, title, status chip. Dead links are
/// struck through and dimmed (transparency, never hidden).
class _SourceCard extends StatelessWidget {
  const _SourceCard({super.key, required this.source});
  final SourceInfo source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dead = source.status == SourceStatus.dead;
    final (chip, color) = switch (source.status) {
      SourceStatus.verified => ('Verified ✓', theme.colorScheme.primary),
      SourceStatus.reachable => ('Reachable', theme.colorScheme.tertiary),
      SourceStatus.dead => ('Dead link ✗', theme.colorScheme.error),
      SourceStatus.checking => ('Checking…', theme.colorScheme.onSurfaceVariant),
    };
    return Opacity(
      opacity: dead ? 0.55 : 1,
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: dead
                  ? theme.colorScheme.error.withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: () => launchUrl(Uri.parse(source.url),
              mode: LaunchMode.externalApplication),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    source.favicon,
                    width: 16,
                    height: 16,
                    errorBuilder: (_, _, _) => Icon(Icons.public,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    source.domain,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        decoration:
                            dead ? TextDecoration.lineThrough : null),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(chip,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: color)),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: Text(
                  source.title ?? source.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      decoration:
                          dead ? TextDecoration.lineThrough : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-character failure — never a stack trace.
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, required this.onRetry});
  final AiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = switch (failure) {
      AuthFailure() =>
        'The provider rejected our key — check Settings.',
      RateLimitFailure() =>
        'Everyone is rate-limited right now. Try again in a moment.',
      NetworkFailure() =>
        'The network ate the request. Check connectivity and retry.',
      _ => 'The verifier glitched. Try again.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verification failed', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(msg, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try again'),
          ),
        ]),
      ),
    );
  }
}

/// Verdict block: summary with citation pills, checks list, routing chips,
/// and the roast card when it's not a pass.
class _VerdictSection extends StatelessWidget {
  const _VerdictSection({
    required this.verdict,
    required this.usedBy,
    required this.rerouted,
    required this.visionSwap,
    required this.roastIsFallback,
    required this.onCitationTap,
    required this.taskId,
  });

  final Verdict verdict;
  final String? usedBy;
  final String? rerouted;
  final String? visionSwap;
  final bool roastIsFallback;
  final ValueChanged<int> onCitationTap;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (verdict.kind) {
      VerdictKind.pass => ('Verified', theme.colorScheme.primary),
      VerdictKind.partial => ('Not quite', theme.colorScheme.tertiary),
      VerdictKind.fail => ('Rejected', theme.colorScheme.error),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: AppSpacing.sm),
      Row(children: [
        _PulseRing(
          fire: verdict.kind == VerdictKind.pass,
          color: color,
          child: AnimatedContainer(
            duration: AppMotion.base,
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
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('${(verdict.confidence * 100).round()}% confident',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xxs, children: [
        if (usedBy != null)
          _Chip(icon: Icons.memory, label: usedBy!),
        if (rerouted != null)
          _Chip(icon: Icons.alt_route, label: rerouted!),
        if (visionSwap != null)
          _Chip(icon: Icons.visibility_outlined, label: visionSwap!),
      ]),
      const SizedBox(height: AppSpacing.md),
      _CitationText(text: verdict.summary, onCitationTap: onCitationTap),
      const SizedBox(height: AppSpacing.md),
      for (final check in verdict.checks)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs + 2),
          child: Row(children: [
            Icon(
              check.ok ? Icons.check_circle : Icons.cancel_outlined,
              size: 16,
              color: check.ok
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
                child: Text(check.label, style: theme.textTheme.bodySmall)),
          ]),
        ),
      if (verdict.roast != null && verdict.kind != VerdictKind.pass)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: RoastCard(
            roast: verdict.roast!,
            fallback: roastIsFallback,
            challenge: verdict.challenge,
            taskId: taskId,
          ),
        ),
    ]);
  }
}

/// Tiny metadata chip (model used / reroute / vision swap).
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// Summary text that reveals word-by-word (streaming feel — it IS the model's
/// text, revealed progressively) with [n] citations as tappable pills.
class _CitationText extends StatefulWidget {
  const _CitationText({required this.text, required this.onCitationTap});
  final String text;
  final ValueChanged<int> onCitationTap;

  @override
  State<_CitationText> createState() => _CitationTextState();
}

class _CitationTextState extends State<_CitationText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<String> _words;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(RegExp(r'(?<=\s)'));
    // ~120ms per word-batch feel: total reveal scales with length.
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_words.length * 30).clamp(400, 3000)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shown = (_words.length * _controller.value).floor();
        final visible = _words.take(shown).join();
        // Parse [n] citations in the revealed prefix.
        final spans = <InlineSpan>[];
        final re = RegExp(r'\[(\d+)\]');
        var last = 0;
        for (final m in re.allMatches(visible)) {
          if (m.start > last) {
            spans.add(TextSpan(
                text: visible.substring(last, m.start),
                style: theme.textTheme.bodyMedium));
          }
          final idx = (int.tryParse(m.group(1)!) ?? 1) - 1;
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () => widget.onCitationTap(idx),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${idx + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary)),
              ),
            ),
          ));
          last = m.end;
        }
        if (last < visible.length) {
          spans.add(TextSpan(
              text: visible.substring(last),
              style: theme.textTheme.bodyMedium));
        }
        return Text.rich(TextSpan(children: spans));
      },
    );
  }
}

/// Screen shake on a `fail` verdict — decays over 400ms, ≤6px amplitude.
/// Pass verdicts trigger a green pulse ring instead (on the badge).
class _VerdictShake extends StatefulWidget {
  const _VerdictShake({required this.verdict, required this.child});
  final VerdictKind? verdict;
  final Widget child;

  @override
  State<_VerdictShake> createState() => _VerdictShakeState();
}

class _VerdictShakeState extends State<_VerdictShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void didUpdateWidget(_VerdictShake old) {
    super.didUpdateWidget(old);
    if (widget.verdict == VerdictKind.fail &&
        old.verdict != VerdictKind.fail &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      // Damped sine: 3 wobbles decaying to zero over 400ms.
      builder: (context, child) => Transform.translate(
        offset: Offset(
          6 * sin(_c.value * 3 * 2 * pi) * (1 - _c.value),
          0,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Expanding ring that fires once behind the verdict badge on a pass — the
/// green pulse moment. Static otherwise.
class _PulseRing extends StatefulWidget {
  const _PulseRing(
      {required this.fire, required this.color, required this.child});
  final bool fire;
  final Color color;
  final Widget child;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
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
    if (widget.fire && !MediaQuery.disableAnimationsOf(context)) {
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Stack(children: [
        if (_c.isAnimating || _c.value > 0 && _c.value < 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RingPulsePainter(
                  t: _c.value,
                  color: widget.color,
                ),
              ),
            ),
          ),
        child!,
      ]),
      child: widget.child,
    );
  }
}

class _RingPulsePainter extends CustomPainter {
  const _RingPulsePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - t) * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width + 28 * t,
      height: size.height + 28 * t,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(999)), paint);
  }

  @override
  bool shouldRepaint(_RingPulsePainter old) => old.t != t;
}
