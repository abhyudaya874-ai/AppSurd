# core/widgets — the animated icon system + shared building blocks

## AnimatedAppIcon (`animated_app_icon.dart`)

Every icon in the shell is a **custom-painted vector icon**, not a stock
Material glyph — no icon-pack dependency, and every icon can animate by
drawing itself via `PathMetric` stroke fractions.

```dart
AnimatedAppIcon(type: AppIconType.tasks, active: selected, size: 21)
```

- One `AnimationController` per icon; `active` runs it forward/reverse.
- `t` (eased 0→1) is shared: each icon maps `t` onto its own draw-in
  choreography (list rows draw one-by-one + tick, gear rotates 90°, the
  plus spins into a ×, trash lid lifts, receipt unrolls, etc.).
- `_seg(i, n)` staggers sub-animations inside an icon.
- Tap → 0.9→1 spring scale. Reduced-motion users get the settled end state.
- Every icon sits in a `RepaintBoundary`.

Types: `tasks, ask, arena, settings, add, orb, trash, filter, verified,
chevron, shield, receipt`.

## The floating tab bar (`features/shell/app_shell.dart`)

Pill-shaped glass bar (`BackdropFilter` + hairline border, one blur layer)
floating ~16px over the bottom edge. A single highlight blob slides +
springs between slots (`AnimatedPositioned`, easeOutBack); the active tab's
label expands beside its icon via `AnimatedSize`. Center slot is the raised
voice-orb button. Tab content is an `IndexedStack` (state preserved), and
the Arena tab only exists while a lineup is selected — `arenaReadyProvider`
hides/shows it.

## Other shared widgets

- `pressable.dart` — spring-scale tap wrapper used on cards/buttons.
- `fade_slide_in.dart` — staggered entrance (`index * stagger` delay).
- `drawn_check.dart` — PathMetric checkmark draw-on.
- `shimmer_box.dart` — loading shimmer block.
