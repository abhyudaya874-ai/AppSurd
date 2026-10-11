import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Staggered entrance: fades in while sliding up 16px. Pass an [index] and
/// each item delays itself by `index * stagger`, so a list builds a cascade
/// without coordinating controllers.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 40),
    this.duration = const Duration(milliseconds: 420),
    this.offset = const Offset(0, 16),
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Duration duration;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    _delay = Timer(widget.stagger * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _controller, curve: AppMotion.standard);
    final slide = Tween<Offset>(
      begin: Offset(widget.offset.dx / 100, widget.offset.dy / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.standard));
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: widget.child),
    );
  }
}
