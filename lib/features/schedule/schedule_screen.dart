import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';

/// Schedule tab — placeholder until the calendar grid lands (kept real so
/// the shell builds at every commit).
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: Center(
            child: Text('Schedule',
                style: AppTypography.display(theme.colorScheme.onSurface,
                    size: 28)),
          ),
        ),
      ),
    );
  }
}
