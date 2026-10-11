import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/motion.dart';

/// Uniform press feedback: scales the child to 0.97 while held and springs
/// back on release. Wraps [child] in a [GestureDetector] — use it for every
/// tappable card/button so the whole app shares one press feel.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
      lowerBound: 0,
      upperBound: 1,
      value: 1,
    );
    _scaleAnim = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    _controller.stop();
    _controller.animateTo(1 - (1 - widget.scale) * 1, duration: AppMotion.fast);
  }

  void _up([TapUpDetails? _]) {
    // Spring back to rest — gives the "tappy" feel rather than a linear return.
    _controller.animateWith(
      SpringSimulation(AppMotion.spring, _controller.value, 1, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _down,
      onTapUp: (d) {
        _up(d);
        widget.onTap?.call();
      },
      onTapCancel: () => _up(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: widget.child,
      ),
    );
  }
}
