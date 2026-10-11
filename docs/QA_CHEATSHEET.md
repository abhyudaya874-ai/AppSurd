# Q&A Cheatsheet — Receipts

Short answers a judge can verify in the code. File references are starting
points, not homework.

## Product

**1. What does the app do?**
A task manager where "done" requires proof. Add task → submit evidence → AI
verdict with real sources → pass completes, anything weaker roasts you and
locks the task behind a timed challenge.

**2. Which three prompt requirements does it hit?**
Evidence-gated completion, AI verification, and a passive-aggressive roast +
accountability challenge on weak evidence. All three are on the happy path.

**3. What makes it different from a todo app?**
There is literally no "mark complete" control. `TaskStatus.done` is only ever
set inside `attachVerdict` after a pass — see `tasks_provider.dart`.

**4. What's the demo path?**
Add task → URL evidence → verdict → then a lazy-text attempt → roast +
challenge. Demo Mode in Settings seeds three labelled tasks; with no API key
the verifier still runs as a labelled `[demo verdict]` over real fetches.

**5. Why the name?**
Receipts = proof. "Show me the receipts" is the whole product thesis.

## Verification & sources

**6. How does a source become "Verified"?**
We fetch it ourselves (`core/net/link_verifier.dart`) — dio GET, 8s timeout,
≤200KB body, HTML stripped via the `html` package. Verified = 2xx AND the
fetched text actually supports a claim (`_reclassify` in
`verification_service.dart`). Reachable = 2xx but no claim match. Dead =
non-2xx/timeout, shown struck-through.

**7. Can a model fake a source?**
No. Sources are URLs *we* fetched. The model can only point at indices into
the list we built — it can suggest, never assert.

**8. What happens on a dead link?**
Forced `fail` in code before the model is even asked
(`evidenceFetchFailed` path). Rule: dead evidence can't be rescued by
prompting.

**9. What does the verdict JSON look like?**
`verdict | confidence | summary | checks[] | claims[] | roast | challenge`.
Schema in `prompts.dart` `verifierSystem`; parsing in `verdict_model.dart`.

**10. What if the model returns garbage?**
`Verdict.parse` extracts the first balanced `{...}` block, tolerates prose
wrapping, and returns a safe "partial" fallback on total failure.

**11. What stops a confident hallucination?**
Two code-level floors: confidence < 0.7 downgrades `pass` → `partial`, and a
non-2xx evidence link is an automatic `fail`. Both are enforced in Dart,
not delegated to the prompt.

**12. How do claims map to sources?**
`claims[].source_index` points into the fetched-source list; a claim counts
as "supported" when ≥50% of its content words appear in that source's
extracted text — cheap, explainable, no embeddings.

**13. What about prompt injection?**
Evidence is wrapped in `<evidence>`/`<source>` delimiters and the system
prompt explicitly tells the model to treat their contents as untrusted data.
Fetched pages can't hijack the instructions.

**14. GitHub evidence?**
`github_client.dart` parses `…/commit/{sha}` and `…/pull/{n}` URLs, fetches
via the public REST API, and hands the model commit message + changed files +
a ≤6KB patch.

**15. Screenshots?**
Downscaled to ≤1280px at capture, sent as base64 image_url parts to a
vision-capable model. If the planned model can't see, the router silently
swaps and the UI shows a "Switched to X to read your screenshot" chip.

## The model router & pill

**16. How does the pill choose a model?**
`ModelRouter.plan` (core/ai/model_router.dart): filter catalog by tier → keep
models whose provider has a key → intersect with live `/models` → sort by
strength → speed bias Groq → append one fallback per other tier.

**17. What happens on a 429 or 5xx?**
`execute()` tries candidates in order: same-tier next provider first, then
the next tier down. The UI shows a "rerouted from X" chip.

**18. What is the strength slider?**
Four detents (Swift/Balanced/Smart/Deep). Custom-painted track + thumb;
thumb stretches while dragging, spring-snaps via `SpringSimulation` on
release, haptic tick at each detent crossing. Selection persists to Hive.

**19. Where do keys live?**
`flutter_secure_storage` (Android Keystore) at runtime; `env.json`
(gitignored) at build time via `--dart-define-from-file`. Never both in the
same write path, never logged, never sent anywhere but the provider's own
base URL.

**20. What if no key is configured?**
The pill still works (entries show locked/dimmed). Verification falls back to
a clearly-labelled `[demo verdict]` that scores the real fetches — the demo
never dead-ends, and it's labelled so it's not fake AI.

## Engineering

**21. State management?**
Riverpod `AsyncNotifier`/`Notifier` — `tasksProvider`, `modelSelectionProvider`,
`demoModeProvider`. No setState for shared state; widgets stay dumb.

**22. Persistence?**
Hive boxes: `receipts_tasks` (tasks+attempts+verdicts as JSON), settings box
for pill selection/demo flag. Kill-restart proofed.

**23. Concurrency/perf choices?**
Link fetching capped at 4 in-flight; page bodies capped ~200KB;
commit patches ≤6KB; lazy `ListView`s; small animated subtrees;
`RepaintBoundary`-style isolation via leaf CustomPainters.

**24. Accessibility?**
`MediaQuery.disableAnimationsOf` is respected — every animated widget reads
it in `didChangeDependencies` (the initState bug we fixed). Fonts bundled so
nothing pops in late.

**25. What would you cut / what's debt?**
Claims cross-check is word-overlap, not semantic similarity; quiz questions
are generated per challenge (falls back to two generic ones); the Linux/web
targets are second-class. All deliberate scope calls for a 6-hour build.

**26. Where's the catch?**
Honest answer: a sufficiently confident liar with a real but irrelevant URL
could pass. The floor is real fetch + claim cross-check + confidence ≥0.7;
the ceiling is whatever model tier you picked. That's the honest answer —
and it's why the pill exists.

## Pitch

**27. Sixty-second version?**
"Productivity apps measure intentions. Receipts measures proof. Evidence or
nothing — and if your evidence is weak, the app tells you so. Beautifully."

**28. What are you most proud of?**
The pill — a router you'd normally hide in settings, turned into the app's
signature interaction. (Alt: the demo-mode honesty — it labels rather than
fakes.)
