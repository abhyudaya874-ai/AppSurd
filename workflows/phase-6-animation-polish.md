# Phase 6 — Animation and Transition Polish (budget: 40 min)

Follow `.devin/rules/04-animation-motion.md`. Work top to bottom; stop when time is up (cut from the bottom).

## Checklist (priority order)
1. Model pill: re-verify the morph, stretching thumb, label cross-fade, provider tint glow, haptics; fix any frame drops.
2. Verdict reveal: pass (green pulse ring + confetti), partial (amber wobble), fail (bounce + shake).
3. Task completion: path-drawn checkmark, confetti once, card collapses to a compact "done" row.
4. Page transitions: shared-axis for forward navigation, fade-through for tab changes, Hero card → detail.
5. Streaming text fade-in per chunk with scroll-follow only when the user is at the bottom.
6. Source card staggered entrance, Verified badge overshoot pop, dead-link shake.
7. App launch sequence (logo draw → list stagger).
8. Pressable feedback on every tappable surface; consistent splash/ripple replacement.
9. Reduced-motion support (`disableAnimations` ⇒ zero-duration).
10. Typing/thinking indicator replacing any bare progress spinner.

## Performance pass
- Run `flutter run --profile` on a real device; open the performance overlay on: task list scroll, pill slider drag, verification screen.
- Add `RepaintBoundary` where raster cost is high; replace `Opacity` with `FadeTransition` in animated trees; limit blur to the pill overlay.

## Exit criteria
- No visible jank on the three screens above. `flutter analyze` clean.
- Commit: "phase 6: animation polish". Update `docs/AI_USAGE.md`.
