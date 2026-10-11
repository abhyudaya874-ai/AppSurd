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

## Round 7 — verification pipeline
Drafted: prompts.dart verifier contract, LinkVerifier (real fetch + html parse,
4-way concurrency), GitHubClient commit/PR fetch, VerifierService event stream,
Verdict model with defensive extract-first-{...} parser and code-enforced
confidence floor.
Adapted: replaced speculative "sources suggested by model" with sources the
app fetched itself; forced-fail on dead link in code, not prompt.
Verified: `flutter analyze` clean; `flutter test` 10/10.

## Round 8 — accountability loop
Drafted: RoastBank (15 non-repeating lines), RoastCard (tilted note + NOPE
stamp + drop-in), CountdownRing, ChallengeScreen (retype/quiz/reupload).
Adapted: quiz questions generated via router with local fallback pair;
reupload completes automatically when a fresh attempt arrives.
Verified: `flutter analyze` clean; running on-device + linux desktop.

## Round 9 — fixes from live run
Found: MediaQuery.disableAnimationsOf called in initState threw on launch —
moved every check to didChangeDependencies.
Found: google_fonts runtime fetch failed on device network — bundled Inter +
Space Grotesk TTFs under assets/fonts and disabled runtime fetching.
Found: ProviderTints extension null in tests — safe ?? fallback.

## Phase 5a additions
- Arena mode: parallel OpenAI-compat calls per judge (max 600 tokens, 30s),
  aggregation computed in Dart — verdict math is never delegated to a model.
- Strictness slider adds one prompt line per detent; thresholds live in code.

## Phase 5b — Voice orb
- `features/voice/` — `Transcriber` interface with three engines:
  `WhisperLocalTranscriber` (whisper_flutter_new, tiny model downloaded at
  runtime from HuggingFace — on-device, labelled), `SystemTranscriber`
  (Android recognizer, streams partials), `GroqWhisperTranscriber`
  (/audio/transcriptions, clearly labelled cloud; only with a Groq key).
- Orb: CustomPainter, one AnimationController; idle/listening(th
  level-reactive)/thinking/speaking/error states; provider-tinted.
- Roast read-aloud via flutter_tts; `voice_quiz` challenge asks aloud and
  judges the spoken answer in code (word overlap).
- Mic audio deleted immediately after transcription; RECORD_AUDIO added.

## Phase 4a — Agentic search
- `core/search/` — Tavily/Exa JSON clients + SearchRouter (intent routing +
  fallback). Keys: Settings + `TAVILY_API_KEY`/`EXA_API_KEY` dart-define.
- `research_pipeline` — Plan(JSON) ⇒ Search(≤3 queries) ⇒ Read(LinkVerifier)
  ⇒ Synthesize(only numbered sources; citations scrubbed in code).
- Research trace UI + Answer/Links tabs; AttachmentBar (Ask + evidence).

## Phase 2a — Free-only models
- `FreeGuard.assertFree` runs before EVERY provider call (router + arena
  judges); a paid model is blocked in code with an in-character error.
- Live `GET /models` builds the catalog: OpenRouter pricing==0 (or :free id),
  NIM curated allowlist ∩ live list, Groq chat-only; raw payloads cached in
  Hive. `StrengthEstimator` computes 0..1 strength; quartiles become the
  4 tiers. `RateLimiter` (≤2 concurrent/provider, spacing, 429+Retry-After
  backoff) wraps every call; request counter in Settings.
- Brand logos bundled (lobe-icons SVGs, SOURCES.md); BrandResolver +
  BrandIcon w/ provider badge + monogram fallback; 15-id test.

## Phase 6 — 5-tab overhaul + schedule + profile
- Drafted: shell rebuild (bottomNavigationBar pill, IndexedStack, tab-state
  providers), Home/Create split with Hero text flight, Tasks group/sort
  popover + collapsing stories header + Focus feed, schedule grid with drag/
  resize/tray/working-hours/auto-schedule, profile account + heatmap + stats.
- Adapted: replaced `StateProvider` (removed in Riverpod 3) with small
  Notifiers; moved group picker into a shared sheet that actually persists
  new groups (the old inline version created un-persisted groups).
- Verified: `flutter analyze` 0 errors/warnings; `flutter test` 42/42
  including new unit tests for sort/group, auto-schedule, working-hours
  validation, contribution stats, and a 5-tab widget test.
