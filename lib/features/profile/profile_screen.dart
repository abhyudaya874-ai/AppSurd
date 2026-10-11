import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';

/// Profile tab — placeholder until account + heatmap land (kept real so the
/// shell builds at every commit).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: Center(
            child: Text('Profile',
                style: AppTypography.display(theme.colorScheme.onSurface,
                    size: 28)),
          ),
        ),
      ),
    );
  }
}
