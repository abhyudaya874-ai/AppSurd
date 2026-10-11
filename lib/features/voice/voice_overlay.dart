import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../model_picker/resolved_model.dart';
import 'transcriber.dart';
import 'voice_engines.dart';
import 'voice_orb.dart';
import '../../core/theme/extensions.dart';

/// What the user intends the transcript to become — proof for a task, or a
/// new task title. Returned to the caller so it can route the text.
enum VoiceIntent { proof, task }

class VoiceResult {
  const VoiceResult(this.text, this.engine, this.elapsedMs);
  final String text;
  final EngineInfo engine;
  final int elapsedMs;
}

/// The orb entry point — a FAB-sized mic button that morphs into the large
/// centered orb. Tap to start/stop, swipe down to cancel.
class VoiceOrbButton extends ConsumerWidget {
  const VoiceOrbButton({super.key, required this.intent, this.onResult});

  final VoiceIntent intent;
  final ValueChanged<VoiceResult>? onResult;

  static Future<VoiceResult?> show(
    BuildContext context, {
    required VoiceIntent intent,
  }) {
    HapticFeedback.selectionClick();
    return showGeneralDialog<VoiceResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, a1, a2) => _VoiceOverlay(intent: intent),
      transitionBuilder: (context, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: AppMotion.standard),
        child: FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tint = ref.watch(resolvedModelProvider) != null
        ? (theme.extension<ProviderTints>() ?? const ProviderTints()).forId(
            ref.watch(resolvedModelProvider)!.provider.id,
          )
        : theme.colorScheme.primary;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: tint.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () async {
            final r = await show(context, intent: intent);
            if (r != null) onResult?.call(r);
          },
          child: Icon(Icons.mic_none_rounded, color: tint),
        ),
      ),
    );
  }
}

/// The full-screen orb sheet.
class _VoiceOverlay extends ConsumerStatefulWidget {
  const _VoiceOverlay({required this.intent});
  final VoiceIntent intent;

  @override
  ConsumerState<_VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends ConsumerState<_VoiceOverlay> {
  Transcriber? _t;
  StreamSubscription? _sub;
  OrbState _orb = OrbState.idle;
  double _level = 0;
  String _partial = '';
  String? _final;
  String? _error;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _t = ref.read(transcriberProvider);
    _sub = _t!.events.listen((e) {
      if (!mounted) return;
      switch (e) {
        case LevelEvent(:final level):
          setState(() => _level = level);
        case PartialEvent(:final text):
          setState(() => _partial = text);
        case FinalEvent(:final text):
          setState(() {
            _orb = OrbState.idle;
            _final = text;
          });
        case TranscriptError(:final failure):
          setState(() {
            _orb = OrbState.error;
            _error = failure.message;
          });
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) setState(() => _orb = OrbState.idle);
          });
      }
    });
    setState(() {
      _orb = OrbState.listening;
      _partial = '';
      _final = null;
      _error = null;
    });
    _stopwatch
      ..reset()
      ..start();
    await _t!.start();
  }

  Future<void> _stop() async {
    HapticFeedback.selectionClick();
    setState(() => _orb = OrbState.thinking);
    await _t!.stop();
    _stopwatch.stop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = ref.watch(resolvedModelProvider) != null
        ? (theme.extension<ProviderTints>() ?? const ProviderTints()).forId(
            ref.watch(resolvedModelProvider)!.provider.id,
          )
        : theme.colorScheme.primary;

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) {
          Navigator.of(context).pop(); // swipe down = cancel
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // The orb — tap toggles start/stop.
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  switch (_orb) {
                    case OrbState.idle:
                      if (_final == null) _start();
                    case OrbState.listening:
                      _stop();
                    case OrbState.error:
                      _start();
                    case _:
                      break;
                  }
                },
                child: VoiceOrb(
                  state: _orb,
                  tint: tint,
                  level: _level,
                  size: 220,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Live transcript / result.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Text(
                    _final ?? _error ?? (_partial.isEmpty ? _hint() : _partial),
                    key: ValueKey(_final ?? _error ?? _partial),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _error != null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Engine chip — always say who transcribed.
              if (_t != null)
                Chip(
                  avatar: Icon(
                    _t!.info.onDevice
                        ? Icons.memory
                        : _t!.info.id == 'system'
                        ? Icons.mic
                        : Icons.cloud_outlined,
                    size: 14,
                  ),
                  label: Text(
                    _t!.info.label,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              const Spacer(),
              if (_final != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            _final = null;
                            _partial = '';
                          }),
                          child: const Text('Retry'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(
                            VoiceResult(
                              _final!.replaceAll(RegExp(r'^\[[\d.]+s\] '), ''),
                              _t!.info,
                              _stopwatch.elapsedMilliseconds,
                            ),
                          ),
                          child: Text(
                            widget.intent == VoiceIntent.proof
                                ? 'Use as proof'
                                : 'Use as task',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_final == null)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.keyboard, size: 16),
                  label: const Text('Type instead'),
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  String _hint() => switch (_orb) {
    OrbState.listening => 'Listening… tap to stop',
    OrbState.thinking => 'Transcribing…',
    _ => 'Tap the orb to speak',
  };
}
