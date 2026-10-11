# AI Usage Log — Receipts

Running log of how AI assistance was used during AppSurd'26. Condensed into
the final 150–200 word declaration in phase 7.

## Tools
- **Devin (SWE-2 Max, Cognition)** — primary coding agent. Wrote all code in
  this repo during the official dev window, guided by `rules/` (00–06) and the
  installed Flutter skills (material-theming, animations, responsive layout).

## Log
- **Phase 1** — Devin scaffolded the project, authored the full theme system
  (color tokens, dark-first ColorScheme pair, Inter + Space Grotesk type scale,
  spacing scale, motion tokens, ThemeExtensions), shared widgets (Pressable,
  FadeSlideIn, ShimmerBox), the path-drawn splash logo, page transitions, and
  docs. Human direction: feature spec, rules files, skill selection, review.
  Human review TODO: walk each theme file, confirm token names match rules.

## In-app AI use (disclosed for judges)
- Groq / NVIDIA NIM / OpenRouter models verify user-submitted evidence and
  generate verdicts, roasts, and quiz challenges.
- Sources shown as "Verified" are fetched and status-checked by the app
  itself — never trusted from the model's output.
