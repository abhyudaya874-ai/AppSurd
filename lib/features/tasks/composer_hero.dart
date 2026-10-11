import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared Hero tag for the composer-text flight: Home's small field and
/// Create Task's big title field share it so the text physically travels.
const String kComposerHeroTag = 'composer-text';

/// Shuttle for the composer→Create Task flight. Both endpoints wrap their
/// [TextField] in a [Hero] with this builder; during the flight we draw a
/// plain text at a lerped size (15 ↔ 28) inside a transparent [Material] so
/// no caret, underline or field chrome flashes mid-air.
Widget composerTextShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  TextField? fieldOf(BuildContext ctx) =>
      (ctx.widget as Hero).child is TextField
      ? (ctx.widget as Hero).child as TextField
      : null;
  final from = fieldOf(fromHeroContext);
  final to = fieldOf(toHeroContext);
  final text =
      (direction == HeroFlightDirection.push ? to : from)?.controller?.text ??
      '';
  final fromSize = from?.style?.fontSize ?? 15;
  final toSize = to?.style?.fontSize ?? 28;
  final theme = Theme.of(flightContext);
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeInOutCubicEmphasized.transform(animation.value);
      return Material(
        type: MaterialType.transparency,
        child: Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: lerpDouble(fromSize, toSize, t),
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );
    },
  );
}
