import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../shell/app_shell.dart';
import 'evidence_sheet.dart';
import 'group_model.dart';
import 'task_card.dart';
import 'task_detail_screen.dart';
import 'task_model.dart';
import 'tasks_provider.dart';

/// One task row with swipe physics: swipe right → "Prove it" opens evidence;
/// long-swipe past → rubber-band "Nice try. Proof first."; swipe left →
/// delete + Undo. When [highlightedTaskProvider] matches this row it plays a
/// one-shot border pulse so a freshly created task is easy to spot.
class TaskRow extends ConsumerStatefulWidget {
  const TaskRow({super.key, required this.task});
  final Task task;

  @override
  ConsumerState<TaskRow> createState() => TaskRowState();
}

class TaskRowState extends ConsumerState<TaskRow>
    with TickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _rubber;
  late final AnimationController _pulse;
  bool _showNope = false;

  static const _proveAt = 88.0; // swipe-right reveal threshold
  static const _nopeAt = 220.0; // long-swipe "nice try" threshold

  @override
  void initState() {
    super.initState();
    _rubber = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() => _dx = _rubber.value);
      });
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _rubber.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dx += d.primaryDelta!;
      if (_dx > _nopeAt) {
        // Rubber-band past the "prove" threshold — resists hard.
        _dx = _nopeAt + (_dx - _nopeAt) * 0.25;
      }
      if (_dx < -160) _dx = -160 + (_dx + 160) * 0.4;
    });
    if (_dx > _proveAt && !_showNope) {
      HapticFeedback.selectionClick();
      _showNope = _dx > _nopeAt;
    }
  }

  void _onDragEnd() {
    final task = widget.task;
    if (_dx > _nopeAt) {
      // Hard long-swipe — playful refusal.
      HapticFeedback.heavyImpact();
      setState(() => _showNope = true);
      _springBack();
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _showNope = false);
      });
    } else if (_dx > _proveAt) {
      // Prove it → evidence sheet.
      _springBack();
      EvidenceSheet.show(context, task);
    } else if (_dx < -70) {
      // Delete with undo.
      _delete();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    _rubber.animateWith(SpringSimulation(AppMotion.spring, _dx, 0, 0));
  }

  void _delete() {
    final t = widget.task;
    ref.read(tasksProvider.notifier).deleteTask(t.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Task deleted'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(tasksProvider.notifier).restoreTask(t)),
    ));
    setState(() => _dx = 0);
  }

  /// Plays the border pulse once when this row becomes the highlighted one.
  void _maybePulse() {
    if (ref.read(highlightedTaskProvider) == widget.task.id &&
        !_pulse.isAnimating &&
        _pulse.value == 0) {
      _pulse.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybePulse();
    final theme = Theme.of(context);
    final t = widget.task;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = _pulse.value < 1
            ? (1 - _pulse.value) * Curves.easeOut.transform(1)
            : 0.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: _pulse.value > 0
                ? Border.all(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.9 * glow),
                    width: 2,
                  )
                : null,
          ),
          child: child,
        );
      },
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: (_) => _onDragEnd(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            // Revealed action layers.
            Positioned.fill(
              child: Row(children: [
                if (_dx > 0)
                  Container(
                    width: _dx.clamp(0.0, _nopeAt + 30),
                    color: _showNope
                        ? theme.colorScheme.error.withValues(alpha: 0.2)
                        : theme.colorScheme.primary.withValues(alpha: 0.15),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Text(
                      _showNope ? 'Nice try. Proof first.' : 'Prove it →',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: _showNope
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary),
                    ),
                  ),
                const Spacer(),
                if (_dx < 0)
                  Container(
                    width: (-_dx).clamp(0.0, 160.0),
                    color: theme.colorScheme.error.withValues(alpha: 0.2),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: AnimatedAppIcon(
                        type: AppIconType.trash,
                        active: _dx < -70,
                        size: 20,
                        color: theme.colorScheme.error),
                  ),
              ]),
            ),
            Transform.translate(
              offset: Offset(_dx, 0),
              child: TaskCard(
                task: t,
                groupName: ref
                    .watch(groupsProvider)
                    .where((g) => g.id == t.groupId)
                    .firstOrNull
                    ?.name,
                accountabilityPending: t.status != TaskStatus.locked &&
                    ref.watch(anyLockedProvider),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => TaskDetailScreen(taskId: t.id))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
