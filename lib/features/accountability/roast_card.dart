import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../verification/verdict_model.dart';
import 'challenge_screen.dart';

/// The roast card — a slightly rotated paper note that drops in with a bounce,
/// stamped "NOPE". Carries the roast text plus the accountability challenge.
/// Tapping "Start challenge" pushes the countdown-ring challenge screen.
class RoastCard extends StatefulWidget {
  const RoastCard({
    super.key,
    required this.roast,
    required this.fallback,
    required this.challenge,
    required this.taskId,
  });

  final String roast;

  /// True when the line came from the local bank — the card notes it quietly.
  final bool fallback;
  final ChallengeDef? challenge;
  final String taskId;

  @override
  State<RoastCard> createState() => _RoastCardState();
}

class _RoastCardState extends State<RoastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drop;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController(vsync: this, duration: AppMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drop.value = 1;
    } else {
      _drop.forward();
      HapticFeedback.mediumImpact();
    }
  }

  bool _speaking = false;
  FlutterTts? _tts;

  Future<void> _speak() async {
    if (_speaking) {
      await _tts?.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    _tts ??= FlutterTts();
    setState(() => _speaking = true);
    await _tts!.setSpeechRate(0.52);
    _tts!.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    await _tts!.speak(widget.roast);
  }

  @override
  void dispose() {
    _tts?.stop();
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curved = CurvedAnimation(parent: _drop, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: _drop,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -60 * (1 - curved.value)),
        child: Opacity(opacity: _drop.value.clamp(0.0, 1.0), child: child),
      ),
      child: Transform.rotate(
        angle: -0.025, // paper-note tilt
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'The auditor has notes',
                        style: theme.textTheme.titleMedium,
                      ),
                      // Read the roast aloud — the orb's speaking state plays
                      // under it on the verdict screen.
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Read aloud',
                        icon: Icon(
                          _speaking
                              ? Icons.volume_up_rounded
                              : Icons.volume_up_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: _speak,
                      ),
                      const Spacer(),
                      // NOPE stamp — pops in late with overshoot.
                      ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _drop,
                          curve: const Interval(
                            0.55,
                            1,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: Transform.rotate(
                          angle: -0.12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.error,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'NOPE',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.error,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.roast,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                  ),
                  if (widget.fallback)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'offline roast · model unavailable',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (widget.challenge != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChallengeScreen(
                            challenge: widget.challenge!,
                            taskId: widget.taskId,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.timer_outlined, size: 18),
                      label: Text('Challenge: ${widget.challenge!.title}'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
