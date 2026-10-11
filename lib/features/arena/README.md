# Arena mode — multi-model jury

`arena_models.dart` — Strictness enum (pass thresholds), JudgeResult (DNF-safe),
ArenaOutcome (consensus + agreement + dissenters + strictest).

`arena_service.dart` — prepare evidence ONCE (shared `prepareEvidence`), fan out
one call per judge concurrently (30s / 600 tokens), aggregate IN CODE:
confidence-weighted vote, ties → stricter verdict, dead-link ⇒ fail,
strictness floor downgrades pass. Roast+challenge come from the strictest judge.
Demo Mode + no keys → canned outcome with a guaranteed dissenter.

`arena_panel.dart` — picker card body in arena mode: provider-grouped
multi-select (2–4), Strictness slider reusing StrengthSlider.

`arena_screen.dart` — jury bar (fill per judge + ms), PageView judge cards
(grid when wide), dashed-border dissent styling, animated consensus meter,
verdict reveal + roast reusing phase 5 components.
