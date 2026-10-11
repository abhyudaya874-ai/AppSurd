import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Keeps content readable on wide windows: centers [child] and caps its width
/// at [AppSpacing.contentMaxWidth] on tablets/web, full width on phones.
/// Decisions use parent constraints (LayoutBuilder), not device type.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? AppSpacing.contentMaxWidth,
        ),
        child: child,
      ),
    );
  }
}
