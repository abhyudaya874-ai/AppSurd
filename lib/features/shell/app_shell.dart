import 'dart:io';

import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/motion.dart';
import '../arena/arena_state.dart';
import '../home/home_screen.dart';
import '../model_picker/model_selection.dart';
import '../arena/arena_info_screen.dart';
import '../playground/playground_screen.dart';
import '../profile/profile_data.dart';
import '../profile/profile_screen.dart';
import '../schedule/schedule_screen.dart';
import '../tasks/tasks_tab_screen.dart';
import 'app_drawer.dart';

/// The visible destination — writable so any screen can navigate (Create
/// Task jumps to Tasks after save) without a navigator hack.
final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(
  NavIndexNotifier.new,
);

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Switches the visible destination (0–4, or 5 for Arena when ready).
  void set(int v) => state = v;
}

/// Id of a freshly created task — the Tasks tab pulses its row once so the
/// user sees where it landed.
final highlightedTaskProvider =
    NotifierProvider<HighlightedTaskNotifier, String?>(
      HighlightedTaskNotifier.new,
    );

class HighlightedTaskNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets (or clears) the highlighted task id.
  void set(String? v) => state = v;
}

/// Lets any descendant open/close the drawer (the avatar button on every
/// page's top-left calls [toggle]).
class DrawerScope extends InheritedWidget {
  const DrawerScope({
    super.key,
    required this.open,
    required this.toggle,
    required super.child,
  });

  final VoidCallback open;
  final VoidCallback toggle;

  static DrawerScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DrawerScope>();

  @override
  bool updateShouldNotify(DrawerScope oldWidget) =>
      open != oldWidget.open || toggle != oldWidget.toggle;
}

/// Avatar button used as the sidebar affordance on every page's top-left —
/// shows the user's photo or initials, tapping it toggles the drawer.
class MenuAvatar extends ConsumerWidget {
  const MenuAvatar({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Semantics(
      label: 'Open navigation menu',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          DrawerScope.of(context)?.toggle();
        },
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          backgroundImage: p.avatarPath != null
              ? FileImage(File(p.avatarPath!))
              : null,
          child: p.avatarPath == null
              ? Text(
                  p.initials,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(fontSize: size * 0.4),
                )
              : null,
        ),
      ),
    );
  }
}

/// The app's persistent shell — a ChatGPT-app-style left sidebar revealed by
/// swiping right (or tapping the avatar). A `Stack`: sidebar layer under a
/// content layer that slides right, rounds its left corners, and dims under
/// a scrim. No package — finger-tracking 1:1, spring settle on release.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _dragStartValue = 0;
  double _dragStartX = 0;
  bool _crossedOpen = false; // haptic once when passing the open threshold

  /// Sidebar width = 84% of the screen, capped at 330dp (ChatGPT-esque).
  double _drawerW(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.84).clamp(0.0, 330.0);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, value: 0);
    // Arena persisted on but lineup is empty — seed once so Arena stays
    // reachable from the sidebar/Ask.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = ref.read(modelSelectionProvider);
      if (sel.arenaMode && sel.arenaLineup.length < 2) {
        final n = ref.read(modelSelectionProvider.notifier);
        for (final id in defaultLineup()) {
          n.toggleArenaModel(id);
        }
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _open() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    _c.animateTo(1, duration: AppMotion.base, curve: AppMotion.standard);
  }

  void _close() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0;
      return;
    }
    _c.animateTo(0, duration: AppMotion.base, curve: AppMotion.standard);
  }

  void _toggle() => _c.value > 0.5 ? _close() : _open();

  // ---- Finger-tracked drawer drag --------------------------------------

  void _dragStart(DragStartDetails d) {
    _dragStartValue = _c.value;
    _dragStartX = d.globalPosition.dx;
    _crossedOpen = _c.value > 0.5;
  }

  void _dragUpdate(DragUpdateDetails d, double w) {
    if (w <= 0) return;
    final next = (_dragStartValue + (d.globalPosition.dx - _dragStartX) / w)
        .clamp(0.0, 1.0);
    final nowOpen = next > 0.5;
    if (nowOpen != _crossedOpen) {
      _crossedOpen = nowOpen;
      HapticFeedback.selectionClick();
    }
    _c.value = next;
  }

  void _dragEnd(DragEndDetails d) {
    final v = (d.primaryVelocity ?? 0).clamp(-1800.0, 1800.0);
    // Direction first, then position — fast flick wins over a 40% drag.
    final target = v > 300
        ? 1.0
        : v < -300
        ? 0.0
        : _c.value > 0.5
        ? 1.0
        : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = target;
      return;
    }
    _c.animateWith(
      SpringSimulation(AppMotion.spring, _c.value, target, v / 1000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navIndexProvider).clamp(0, 5);
    final arenaReady = ref.watch(arenaReadyProvider);
    final w = _drawerW(context);
    final isHome = index == 0;

    // Destinations — Arena only exists when a lineup is configured.
    final pages = <Widget>[
      const HomeScreen(),
      const TasksTabScreen(),
      const ScheduleScreen(),
      const PlaygroundScreen(),
      const ProfileScreen(),
      if (arenaReady) const ArenaDestinationPage(),
    ];
    final tab = index.clamp(0, pages.length - 1);

    return DrawerScope(
      open: _open,
      toggle: _toggle,
      child: PopScope(
        canPop: _c.value < 0.05,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close(); // drawer eats the first back press
        },
        child: Scaffold(
          body: Stack(
            children: [
              // ---- Sidebar layer (full height, fixed width) ----
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: w,
                child: RepaintBoundary(
                  child: AppDrawer(
                    width: w,
                    pageCount: pages.length,
                    onNavigate: (i) {
                      ref.read(navIndexProvider.notifier).set(i);
                      _close();
                    },
                    onClose: _close,
                  ),
                ),
              ),

              // ---- Content layer (slides + rounds + dims) ----
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final t = _c.value;
                  return Transform.translate(
                    offset: Offset(w * t, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(28 * t),
                      ),
                      child: Stack(
                        children: [
                          child!,
                          // Dim scrim — taps close the drawer.
                          IgnorePointer(
                            ignoring: t == 0,
                            child: GestureDetector(
                              onTap: _close,
                              onHorizontalDragUpdate: (d) => _dragUpdate(d, w),
                              onHorizontalDragEnd: _dragEnd,
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.35 * t),
                              ),
                            ),
                          ),
                          // Left-edge swipe zone on non-Home destinations so
                          // Schedule's horizontal panning never fights.
                          if (!isHome && t == 0)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 24,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragStart: _dragStart,
                                onHorizontalDragUpdate: (d) =>
                                    _dragUpdate(d, w),
                                onHorizontalDragEnd: _dragEnd,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                // On Home the WHOLE content is the drag surface (spec);
                // elsewhere only the 24dp edge zone above opens the drawer.
                child: isHome
                    ? GestureDetector(
                        onHorizontalDragStart: _dragStart,
                        onHorizontalDragUpdate: (d) => _dragUpdate(d, w),
                        onHorizontalDragEnd: _dragEnd,
                        child: _content(tab, pages),
                      )
                    : _content(tab, pages),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Destination pages in an IndexedStack so each keeps its scroll/state,
  /// with a short fade on switch.
  Widget _content(int tab, List<Widget> pages) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(tab),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.standard,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: IndexedStack(index: tab, children: pages),
    );
  }
}
