import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// Small pill chip shared by the Home composer, suggestion row, Tasks filter
/// bar and Create Task pickers. `filled` = selected/accented state.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.onTap,
    this.filled = false,
    this.trailing,
    this.leading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: filled
          ? theme.colorScheme.primary.withValues(alpha: 0.18)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: filled
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outline,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ?leading,
            Text(label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: filled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant)),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}
