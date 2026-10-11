# 01 — Flutter Architecture

## Stack
- Flutter stable, Dart 3, Material 3 (heavily customised; do not ship default-looking widgets).
- State management: **flutter_riverpod** (Notifier / AsyncNotifier). No setState for anything shared.
- Networking: **dio** (needed for streaming responses).
- Local storage: **hive_ce** + **hive_ce_flutter** for tasks and chat history; **flutter_secure_storage** for API keys entered in-app.
- Navigation: plain `Navigator` with custom `PageRouteBuilder` transitions (see `04-animation-motion.md`). Avoid heavy routing packages.
- UI helpers: **flutter_animate**, **google_fonts**, **flutter_markdown**, **url_launcher**, **image_picker**, **confetti**.
- Add a package only when it saves real time, and record it in `docs/DEPENDENCIES.md` with a one-line reason
  (all third-party packages must be disclosed at submission).

## Folder structure (feature-first)
```
lib/
  main.dart
  app.dart                      # MaterialApp, theme, root route
  core/
    theme/                      # colors, typography, motion tokens (durations, curves)
    ai/                         # provider clients, model catalog, router (see 02-model-router.md)
    net/                        # dio setup, SSE stream parser, link verifier
    widgets/                    # shared animated widgets
    utils/
  features/
    tasks/                      # task list, add task, task detail, evidence capture
    verification/               # verifier agent, verdict model, sources UI
    accountability/             # roast + challenge UI and logic
    model_picker/               # THE pill selector and slider
    settings/                   # API keys screen
docs/
  ARCHITECTURE.md  DEPENDENCIES.md  AI_USAGE.md
```

## Code rules
- Files under ~250 lines. One widget class per file when it exceeds ~80 lines.
- Immutable models (`final` fields, `copyWith`). Hand-write `toJson`/`fromJson` — no code generation, no build_runner
  (saves time and keeps the code explainable).
- No business logic in widgets. Widgets read providers and call notifier methods.
- All colors, durations, curves come from `core/theme` tokens. No magic numbers scattered in widgets.
- Handle loading, empty, and error states for every async UI. Errors are shown in-character (friendly, never a raw stack trace).
- Null safety strictly respected; avoid `!` unless provably safe.
- Target Android first. Web is optional (CORS blocks most provider and page fetches in browsers).
