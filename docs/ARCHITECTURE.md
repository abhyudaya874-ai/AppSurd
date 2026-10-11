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
    ai/                      provider client, model catalog, router   [phase 2]
    net/                     dio setup, link verifier, GitHub client  [phase 4]
    widgets/                 Pressable, FadeSlideIn, ShimmerBox
    utils/                   responsive helpers, page transitions
  features/
    splash/                  animated logo launch sequence
    tasks/                   task list, detail, evidence capture      [phase 3]
    verification/            verifier agent + verdict + sources UI    [phase 4]
    accountability/          roast card + challenge logic             [phase 5]
    model_picker/            pill selector + strength slider          [phase 2]
    settings/                API keys + demo mode                     [phase 2]
```

## Data flow (target, end of phase 5)

```
User adds task ──► Hive (tasks box) ──► task list (AsyncNotifier)
Submit evidence ──► VerifierService ──► link fetch (dio) + model call (router)
                 ──► Verdict {pass|partial|fail, checks, claims, sources}
pass ─► task done + integrity up
partial/fail ─► roast + accountability challenge ─► task locked ─► retry
```

## Rules in force

- State: Riverpod `Notifier`/`AsyncNotifier` only — no setState for shared state.
- ThemeData is the single source of truth for color/type/spacing; widgets read
  `Theme.of(context)`, never hardcode styles.
- Motion tokens in `core/theme/motion.dart`; accessibility reduced-motion
  collapses all durations to zero.
- No code generation anywhere; models are hand-written immutable classes.
