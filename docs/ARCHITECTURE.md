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

## Phase 5b — Voice orb (done)
- `features/voice/` — orb painter + overlay + three-engine transcriber.
- Entry points: task-list mic FAB (dictate a task), evidence-sheet "Speak it".
- Privacy: WAV deleted after transcription; cloud engine labelled; Settings
  picks the engine with availability dimming.

## Phase 3a — UI revamp (done)
- Palette rule 09: near-black `#0B0D10`, hairline `rgba(255,255,255,.08)`
  borders, radius 24 cards. Fonts bundled in `assets/fonts/`: Inter (UI),
  Space Grotesk (headings), **Fraunces serif** (display headlines) —
  registered in pubspec `fonts:` (GoogleFonts runtime fetch is OFF).
- `CupertinoPageTransitionsBuilder` for all platforms — every push slides
  over with parallax + edge-swipe back.
- `core/widgets/animated_app_icon.dart` — painted icons w/ draw-on animation.
- `features/shell/app_shell.dart` — IndexedStack tabs + floating glass bar
  (sliding blob, expanding label, raised orb). Arena tab hidden until a
  lineup exists.
- Composer card on Tasks home; FAB removed. Swipe right = Prove it, hard
  long-swipe = "Nice try. Proof first." rubber-band, swipe left = delete
  + Undo. Groups (name+color, persisted) with collapsible sections and a
  filter chip bar.
- Pill v2: dot-matrix glyph (tier = lit count), halftone-dot slider fill,
  big white thumb — routing/haptics unchanged.

## Phase 4a — Agentic search + attachments (done)
- `core/search/` — Tavily + Exa clients (plain JSON POSTs), `SearchRouter`
  (intent ⇒ provider, Auto/Tavily/Exa/Off override, cross-fallback).
- `features/research/` — `ResearchPipeline` (Plan ⇒ Search ⇒ Read ⇒
  Synthesize, JSON-driven so any model can plan), `AttachmentBar`
  (≤4 images, downscale+re-encode, Hero preview), `ResearchTraceView`
  (collapsible timer header, step/query/source tree, favicons, status
  chips, source detail sheet).
- Ask composer: Search ▾ + Agentic ▾ chips, eye-icon vision-routing swap.
- Citation scrub: `[n]` beyond retrieved sources and model-written URLs are
  stripped — only our own records render as links.

## Phase 6 — 5-tab shell overhaul (done)
- `features/shell/app_shell.dart` — fixed 5-tab `Scaffold.bottomNavigationBar`
  glass pill (Home · Tasks · Schedule · Ask · Profile). Equal `Expanded`
  slots, Material icons always visible, blob position = width/5, bar slides
  down when the keyboard opens. `shellTabProvider`/`highlightedTaskProvider`
  let deep screens switch tabs / pulse a new row.
- `features/home/home_screen.dart` — Perplexity-style input only (mark,
  integrity chip, headline, composer, suggestion chips). Send pushes
  `CreateTaskScreen` via a Hero text flight (15→28sp, transparent Material
  shuttle) on a 420ms emphasized route.
- `features/tasks/` — `create_task_screen.dart` (proof, group, due, priority,
  duration), `task_view_options.dart` (persisted group-by/sort-by + pure
  groupTasks/sortTasks), `tasks_tab_screen.dart` (collapsing stories-avatar
  SliverPersistentHeader, two-stage view popover, search, status chips),
  `focus_view.dart` (vertical PageView snap feed), `task_row.dart` (swipe
  prove/delete + new-row pulse).
- `features/schedule/` — `schedule_screen.dart` (24h shared scroll × 5-day
  PageView columns, now-line, long-press drag with 15-min snap + cross-day
  ghost, bottom-handle resize, edge auto-scroll, DragTarget tray chips,
  long-press quick-create), `working_hours.dart` + `working_hours_editor.dart`
  (per-day ranges, validated, shaded on grid), `auto_schedule.dart` (greedy
  priority-ordered placement), `block_layout.dart` (overlap lanes).
- `features/profile/` — `profile_data.dart` (local account in Hive),
  `contribution_stats.dart` (streaks/total/best day), `contribution_heatmap.dart`
  (53×7 single-painter grid, diagonal stagger, tap → day card; Receipts mode
  via `completedAt`, GitHub mode via `fetchContributionCalendar` + 6h cache),
  `profile_screen.dart` (edit sheet, stats, export JSON, ~60-day demo seed,
  reset). Settings + Arena are pushed routes (Arena also in Ask's app bar).

## Phase 6 rev2 — sidebar navigation (final shell)
- Bottom tab bar removed entirely. `app_shell.dart` is a Stack: `AppDrawer`
  layer under a content layer that slides right `drawerW*t`, rounds left
  corners (28dp), and dims under a tap-to-close scrim. Finger-tracked 1:1;
  release settles via `SpringSimulation(AppMotion.spring)` on
  velocity+position. Home: full-width right-swipe opens; elsewhere a 24dp
  left-edge zone only. `PopScope` makes back close the drawer first.
- `app_drawer.dart` — ChatGPT-style: search (live-filters recents, submit →
  Tasks via `tasksSearchProvider`), nav rows, last-8 recents w/ status dots,
  footer profile+integrity+gear. `navIndexProvider` + `IndexedStack`.
- Home = Perplexity layout: avatar / Task·Ask segment pill / integrity button;
  centred mark + tagline + fading suggestions; bottom-pinned composer
  (+ sheet, ModelPill, group, mic, white round send: waveform→arrow).
  Ask mode seeds `askSeedProvider` into the Ask composer.
