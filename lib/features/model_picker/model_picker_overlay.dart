import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import 'picker_card.dart';

/// The floating card the pill morphs into. Rendered in an [OverlayEntry]:
/// a scrim barrier (tap-outside dismiss) plus a card anchored to the pill's
/// screen rect, growing from pill size to full size (the shared-element morph)
/// and clamped so it can never run off-screen — keyboard included.
class ModelPickerOverlay extends StatefulWidget {
  const ModelPickerOverlay({
    super.key,
    required this.link,
    required this.morph,
    required this.anchorRect,
    required this.onDismiss,
  });

  /// Unused for positioning math but kept for future shared-element upgrades.
  final LayerLink link;
  final AnimationController morph;
  final Rect anchorRect;
  final VoidCallback onDismiss;

  @override
  State<ModelPickerOverlay> createState() => _ModelPickerOverlayState();
}

class _ModelPickerOverlayState extends State<ModelPickerOverlay> {
  static const double _cardW = 360;
  static const double _cardH = 470;

  double _dragOffset = 0; // pull-down-to-dismiss progress

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final keyboard = mq.viewInsets.bottom;
    const margin = 12.0;
    const gap = 10.0;

    final cardW = _cardW.clamp(0.0, screen.width - margin * 2);
    final cardH = _cardH.clamp(0.0, screen.height - margin * 2 - keyboard);

    // Horizontal clamp: keep the card fully on-screen.
    final left = widget.anchorRect.left
        .clamp(margin, screen.width - cardW - margin)
        .toDouble();

    // Prefer opening upward (composer sits low); flip down if there is
    // more room below the pill than above it.
    final spaceAbove = widget.anchorRect.top - margin;
    final spaceBelow =
        screen.height - keyboard - widget.anchorRect.bottom - margin;
    final openUp = spaceAbove >= cardH + gap || spaceAbove > spaceBelow;
    final top = openUp
        ? (widget.anchorRect.top - cardH - gap)
            .clamp(margin, screen.height - cardH - keyboard - margin)
        : (widget.anchorRect.bottom + gap)
            .clamp(margin, screen.height - cardH - keyboard - margin);

    return Stack(
      children: [
        // Scrim — tap outside dismisses.
        GestureDetector(
          onTap: widget.onDismiss,
          behavior: HitTestBehavior.opaque,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: widget.morph,
              curve: const Interval(0, 0.4),
            ),
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
        ),
        // The morphing card.
        Positioned(
          left: left,
          top: top,
          width: cardW,
          height: cardH,
          child: AnimatedBuilder(
            animation: widget.morph,
            builder: (context, child) {
              final t = AppMotion.standard.transform(widget.morph.value);
              // Grow from pill-sized to full card — anchored at the edge that
              // touches the pill so it reads as "the pill became the card".
              final fromH = widget.anchorRect.height;
              final h = fromH + (cardH - fromH) * t;
              final w = (widget.anchorRect.width + (cardW - widget.anchorRect.width) * t)
                  .clamp(0.0, cardW);
              final alignY = openUp ? -1.0 : 1.0;
              return Align(
                alignment: Alignment(0, alignY),
                heightFactor: 1,
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20 + 4 * (1 - t)),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: Opacity(
                        opacity: (widget.morph.value - 0.25).clamp(0, 1) / 0.75,
                        child: child,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              elevation: 12,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onVerticalDragUpdate: (d) => setState(() {
                  _dragOffset = (_dragOffset + d.delta.dy).clamp(0.0, 160);
                }),
                onVerticalDragEnd: (d) {
                  if (_dragOffset > 70 || (d.primaryVelocity ?? 0) > 500) {
                    widget.onDismiss();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                },
                child: const PickerCard(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
