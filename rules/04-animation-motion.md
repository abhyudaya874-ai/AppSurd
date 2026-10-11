# 04 — Animation and Motion System

Goal: the app should feel as fluid as Telegram, ChatGPT, and Claude mobile. Motion explains state; it is not decoration.

## Motion tokens (define once in `core/theme/motion.dart`)
- Durations: `fast 150ms`, `base 260ms`, `slow 420ms`, `hero 520ms`.
- Curves: `standard = Curves.easeOutCubic`, `emphasized = Curves.easeInOutCubicEmphasized`, springs via `SpringDescription(mass: 1, stiffness: 320, damping: 26)`.
- Always read `MediaQuery.disableAnimationsOf(context)` — when true, collapse durations to zero.

## Required motion moments
1. **App launch**: logo mark draws in, then cross-fades into the task list; list items stagger in (40 ms apart, fade + 16 px slide-up).
2. **Page transitions**: custom `PageRouteBuilder` — shared-axis (slide + fade) for forward navigation, fade-through for tab switches.
   Task card → task detail uses `Hero` on the card container and title.
3. **Task list**: `AnimatedList` for add/remove; swipe actions with spring-back; completed tasks animate a path-drawn checkmark,
   confetti burst (once), and the card smoothly collapses its height to a "done" row.
4. **Evidence capture**: segmented control for evidence type with a sliding indicator; the input area cross-fades with `AnimatedSwitcher`
   (size-aware). Picked screenshot appears with a scale-in + soft shadow.
5. **Verification progress**: step list as in `03-verification-agent.md`; checkmarks draw via `CustomPainter` + `PathMetric`.
6. **Streaming text**: new tokens fade in (opacity 0→1 over 120 ms) rather than popping; auto-scroll follows the stream only if the user is at the bottom.
7. **Source cards**: stagger in from the right; "Verified ✓" badge pops with an overshoot spring; dead links shake once horizontally then dim.
8. **Verdict reveal**: pass = green pulse ring + confetti; partial = amber wobble; fail = the roast card drops in with a bounce and a short
   horizontal shake of the whole screen (≤ 6 px amplitude, 400 ms), plus `HapticFeedback.mediumImpact()`.
9. **Accountability challenge**: circular countdown ring (CustomPainter, smooth `AnimationController`, not per-second jumps);
   the ring color shifts from calm to urgent in the last 10 seconds.
10. **Model pill**: all behaviors in `02-model-router.md` (morph, stretching thumb, label cross-fade, provider tint glow).
11. **Typing / thinking indicator**: three-dot wave or shimmer — never a bare `CircularProgressIndicator`.
12. **Press feedback**: every tappable card/button scales to 0.97 on press-down with a spring return (shared `Pressable` widget).

## Performance rules
- Wrap heavy animated subtrees in `RepaintBoundary`.
- Prefer `AnimatedBuilder` with a `child` argument so static subtrees are not rebuilt.
- Avoid `Opacity` on large subtrees inside animations; use `FadeTransition`.
- No `BackdropFilter` blur over scrolling lists (jank on mid-range phones). Use one blurred layer max, only on the pill overlay.
- Test on a real device in `--profile` mode before the submission freeze.

## Visual identity
- Dark-first theme with a light variant. Deep neutral background, one vivid accent, per-provider tints
  (Groq = orange, NVIDIA = green, OpenRouter = violet) used sparingly (pill glyph, source chips, slider gradient).
- Typography: Inter (body) + a characterful display face for headings and roast text (e.g. Space Grotesk or Fraunces).
- Roast card has its own personality: slightly rotated paper-note look, handwriting-ish accent font, subtle sticker-style "NOPE" stamp animation.
