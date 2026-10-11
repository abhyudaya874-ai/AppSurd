import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/net/github_client.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/transitions.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/shimmer_box.dart';
import '../arena/arena_info_screen.dart';
import '../arena/arena_state.dart';
import '../settings/settings_screen.dart';
import '../shell/app_shell.dart';
import '../tasks/task_model.dart';
import '../tasks/tasks_provider.dart';
import 'contribution_heatmap.dart';
import 'contribution_stats.dart';
import 'profile_data.dart';

/// Profile tab — local account card, integrity stats, the contribution
/// heatmap (Receipts or scraped GitHub), and data actions (export, demo
/// data, reset). Settings + Arena are pushed routes from here.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _githubMode = false;

  /// GitHub contributions for the saved username — cached in Hive for 6h so
  /// the map works offline after the first fetch.
  static const _cacheKey = 'gh_contrib';
  Future<Map<DateTime, int>?> _githubContrib(String user) async {
    final box = await Hive.openBox('receipts_settings');
    final raw = box.get(_cacheKey);
    if (raw is Map && raw['user'] == user) {
      final at = DateTime.tryParse(raw['at'] as String? ?? '');
      if (at != null &&
          DateTime.now().difference(at) < const Duration(hours: 6)) {
        return _decodeContrib(raw['data']);
      }
    }
    final res = await GitHubClient().fetchContributionCalendar(user);
    if (res == null) return _decodeContrib(raw is Map ? raw['data'] : null);
    final data = {
      for (final e in res.entries) e.key.toIso8601String(): e.value.count,
    };
    await box.put(_cacheKey, {
      'user': user,
      'at': DateTime.now().toIso8601String(),
      'data': data,
    });
    return {for (final e in res.entries) e.key: e.value.count};
  }

  Map<DateTime, int>? _decodeContrib(Object? raw) {
    if (raw is! Map) return null;
    final out = <DateTime, int>{};
    for (final e in raw.entries) {
      final d = DateTime.tryParse(e.key as String? ?? '');
      if (d != null) out[d] = (e.value as num?)?.toInt() ?? 0;
    }
    return out.isEmpty ? null : out;
  }

  /// "N tasks verified on `<date>`" — bottom card listing titles.
  void _showDay(DateTime day, int count) {
    final tasks = ref.read(tasksProvider).value ?? const [];
    final dayTasks = tasks
        .where(
          (t) =>
              t.completedAt != null &&
              DateTime(
                    t.completedAt!.year,
                    t.completedAt!.month,
                    t.completedAt!.day,
                  ) ==
                  DateTime(day.year, day.month, day.day),
        )
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count verified · ${day.day}/${day.month}/${day.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              if (dayTasks.isEmpty)
                Text(
                  'Nothing on this day.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final t in dayTasks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${t.title}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final p = ref.read(profileProvider);
    final name = TextEditingController(text: p.name);
    final gh = TextEditingController(text: p.githubUser);
    String? avatar = p.avatarPath;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit profile',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final f = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 256,
                      );
                      if (f != null) set(() => avatar = f.path);
                    },
                    child: CircleAvatar(
                      radius: 26,
                      backgroundImage: avatar != null
                          ? FileImage(File(avatar!))
                          : null,
                      child: avatar == null
                          ? const Icon(Icons.add_a_photo_outlined, size: 18)
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: gh,
                decoration: const InputDecoration(
                  labelText: 'GitHub username (optional)',
                  hintText: 'for the public contribution graph',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(profileProvider.notifier)
          .save(
            Profile(
              name: name.text.trim(),
              githubUser: gh.text.trim(),
              avatarPath: avatar,
            ),
          );
    }
  }

  Future<void> _export() async {
    final tasks = ref.read(tasksProvider).value ?? const [];
    final json = const JsonEncoder.withIndent('  ')
        .convert([for (final t in tasks) t.toJson()]);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All task data copied as JSON.')),
      );
    }
  }

  /// Seeds ~60 days of verified demo tasks so the heatmap/stats/streaks are
  /// demoable without real AI calls. Deterministic count pattern.
  Future<void> _loadDemo() async {
    final n = ref.read(tasksProvider.notifier);
    final existing = ref.read(tasksProvider).value ?? const [];
    if (existing.any((t) => t.isDemo && t.status == TaskStatus.done)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demo data already loaded.')),
        );
      }
      return;
    }
    final now = DateTime.now();
    var seed = 7;
    int next() => (seed = (seed * 1103515245 + 12345) % 2147483648);
    for (var d = 59; d >= 0; d--) {
      final count = next() % 3; // 0–2 tasks most days
      for (var i = 0; i < count; i++) {
        final when = DateTime(
          now.year,
          now.month,
          now.day - d,
          9 + next() % 10,
          next() % 60,
        );
        final t = await n.addTask(
          title: 'Demo: finished work #${60 - d}-${i + 1}',
          description: 'Seeded demo evidence',
        );
        await n.addAttempt(
          t.id,
          EvidenceAttempt(
            id: 'demo-${t.id}-$i',
            type: EvidenceType.text,
            payload: 'demo',
            submittedAt: when,
            verdictJson: const {'status': 'pass'},
          ),
          status: TaskStatus.verifying,
        );
        await n.attachVerdict(
          t.id,
          const {'status': 'pass'},
          status: TaskStatus.done,
          integrityDelta: 4,
        );
        final done = t.id;
        final cur = (ref.read(tasksProvider).value ?? const []).firstWhere(
          (x) => x.id == done,
        );
        await n.updateTask(cur.copyWith(isDemo: true));
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Demo data loaded.')));
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all data?'),
        content: const Text(
          'Deletes every task, group, view option, working-hours and '
          'profile entry. API keys are kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final tasks = await Hive.openBox('receipts_tasks');
    await tasks.clear();
    final settings = await Hive.openBox('receipts_settings');
    for (final k in [
      'profile',
      'taskView',
      'workingHours',
      'groups',
      _cacheKey,
    ]) {
      await settings.delete(k);
    }
    ref.invalidate(tasksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);
    final tasks = ref.watch(tasksProvider).value ?? const [];
    final arenaReady = ref.watch(arenaReadyProvider);
    final integrity = ref.watch(integrityScoreProvider);
    final byDay = receiptsByDay(tasks);
    final stats = computeStats(byDay, DateTime.now());
    final barPad = 24.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              barPad,
            ),
            children: [
              Row(
                children: [
                  const MenuAvatar(size: 30),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Profile',
                    style: AppTypography.grotesk(theme.colorScheme.onSurface)
                        .copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- Account card ----
              FadeSlideIn(
                child: Card(
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: theme.colorScheme.outline),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundImage: profile.avatarPath != null
                          ? FileImage(File(profile.avatarPath!))
                          : null,
                      child: profile.avatarPath == null
                          ? Text(
                              profile.initials,
                              style: theme.textTheme.titleMedium,
                            )
                          : null,
                    ),
                    title: Text(
                      profile.name.isEmpty ? 'Set your name' : profile.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      profile.githubUser.isEmpty
                          ? 'Local account · no cloud'
                          : 'github.com/${profile.githubUser}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Edit profile',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _editProfile,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ---- Stats row ----
              FadeSlideIn(
                index: 1,
                child: Row(
                  children: [
                    _stat(theme, '${stats.currentStreak}', 'streak'),
                    _stat(theme, '${stats.longestStreak}', 'best streak'),
                    _stat(theme, '${stats.total}', 'verified'),
                    _stat(theme, '$integrity', 'integrity'),
                  ],
                ),
              ),
              if (stats.bestDay != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Best day: ${stats.bestDay!.day}/${stats.bestDay!.month} '
                    '(${stats.bestCount} verified)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Heatmap header + toggle ----
              FadeSlideIn(
                index: 2,
                child: Row(
                  children: [
                    Text('Contributions', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    _seg(
                      theme,
                      'Receipts',
                      !_githubMode,
                      () => setState(() => _githubMode = false),
                    ),
                    const SizedBox(width: 4),
                    _seg(
                      theme,
                      'GitHub',
                      _githubMode,
                      () => setState(() => _githubMode = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                index: 3,
                child: _githubMode
                    ? _githubHeatmap(theme, profile.githubUser)
                    : ContributionHeatmap(
                        contributions: byDay,
                        onTapDay: _showDay,
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ---- Rows ----
              _row(
                theme,
                Icons.key_rounded,
                'API keys & models',
                'Providers, keys, demo mode',
                () {
                  Navigator.of(context)
                      .push(AppTransitions.sharedAxis(const SettingsScreen()));
                },
              ),
              if (arenaReady)
                _row(
                  theme,
                  Icons.groups_rounded,
                  'Arena lineup',
                  'Jury judging every submission',
                  () {
                    Navigator.of(
                      context,
                    ).push(AppTransitions.sharedAxis(const ArenaInfoScreen()));
                  },
                ),
              _row(
                theme,
                Icons.ios_share_rounded,
                'Export data',
                'Copy all tasks as JSON',
                _export,
              ),
              _row(
                theme,
                Icons.auto_awesome_rounded,
                'Load demo data',
                '~60 days of verified tasks',
                _loadDemo,
              ),
              _row(
                theme,
                Icons.delete_outline_rounded,
                'Reset all data',
                'Wipe tasks, groups and settings',
                _reset,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _githubHeatmap(ThemeData theme, String user) {
    if (user.isEmpty) {
      return _emptyBox(
        theme,
        'Set a GitHub username in Edit profile to see its graph.',
      );
    }
    return FutureBuilder<Map<DateTime, int>?>(
      future: _githubContrib(user),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 120, child: ShimmerBox());
        }
        final data = snap.data;
        if (data == null) {
          return _emptyBox(
            theme,
            'Couldn\'t fetch GitHub contributions (offline?). Cached data appears here after the first fetch.',
          );
        }
        return ContributionHeatmap(contributions: data, onTapDay: _showDay);
      },
    );
  }

  Widget _emptyBox(ThemeData theme, String msg) => Container(
    height: 120,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.colorScheme.outline),
    ),
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Text(
      msg,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _seg(ThemeData theme, String label, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        tap();
      },
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.fast),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: on
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: on
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.headlineMedium),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: color.withValues(alpha: 0.85)),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(color: color),
      ),
      subtitle: Text(
        sub,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
