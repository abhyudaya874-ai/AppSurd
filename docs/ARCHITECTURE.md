# Architecture — Receipts

Feature-first Flutter app. No backend; all state is local (Hive), all AI calls
go straight from the app to OpenAI-compatible provider APIs.

## Layers

```
lib/
  main.dart                  boots Hive + ProviderScope
  app.dart                   MaterialApp, dark-first themes
  core/
    theme/                   colors, spacing, typography, motion tokens,
                             ThemeExtensions (ProviderTints, MotionTokens)
    ai/                      provider client, model catalog, router, prompts
    net/                     link verifier (real fetches), GitHub client
    widgets/                 Pressable, FadeSlideIn, ShimmerBox, DrawnCheck
    utils/                   responsive helpers, page transitions
  features/
    splash/                  animated logo launch sequence
    tasks/                   task list, detail, evidence capture
    verification/            verifier service + verdict + sources UI
    accountability/          roast bank/card, countdown ring, challenges
    model_picker/            pill selector + strength slider
    settings/                API keys + demo mode
```

## Data flow (implemented)

```
User adds task ──► Hive (tasks box) ──► task list (AsyncNotifier)
Submit evidence ──► VerifierService (Stream<VerificationEvent>)
                 ──► LinkVerifier / GitHubClient  (app fetches — not the model)
                 ──► model call via ModelRouter.execute (tier → provider
                     candidates, retry on 429/5xx/timeout, vision swap)
                 ──► Verdict {pass|partial|fail, confidence, checks,
                     claims, roast, challenge} parsed defensively
pass ─► task done + integrity +10 + confetti + pulse ring
partial/fail ─► roast card + countdown challenge ─► task locked
             ─► challenge done ─► task open again (+2 if fast)
No keys? ─► labelled "[demo verdict]" heuristic over the REAL fetches.
```

## Rules in force

- State: Riverpod `Notifier`/`AsyncNotifier` only — no setState for shared state.
- ThemeData is the single source of truth for color/type/spacing; widgets read
  `Theme.of(context)`, never hardcode styles.
- Motion tokens in `core/theme/motion.dart`; accessibility reduced-motion
  collapses all durations to zero.
- No code generation anywhere; models are hand-written immutable classes.

## Phase 5a — Arena mode (done)
- `features/arena/` — jury of 2–4 models judging the same evidence.
- Shared prep: `evidence_prep.dart` (fetch once, all judges see identical sources).
- Aggregation is pure code: confidence-weighted vote, ties→strict, strictness
  floor on pass, strictest judge supplies roast+challenge.
- UI: jury bar + paged judge cards + dissent tags + animated consensus meter.
