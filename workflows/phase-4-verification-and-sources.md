# Phase 4 — Verification Agent and Verified Sources (budget: 50 min)

Follow `.devin/rules/03-verification-agent.md`. **Never display a link the app did not fetch itself.**

## Steps
1. `core/net/link_verifier.dart`: `verify(Uri) -> LinkCheck { status, finalUrl, title, description, textExtract, ok }`
   (8 s timeout, redirects, 200 KB cap, tag stripping). Concurrency-limited to 4 simultaneous fetches.
2. `core/net/github_client.dart`: fetch commit message, changed file names, trimmed patch (≤ 6 KB) for commit evidence.
3. `core/ai/prompts.dart`: verifier system prompt with prompt-injection defence (untrusted data in delimiters), the JSON contract,
   and 3 few-shot examples of the roast voice. Comment every constant.
4. `features/verification/verdict_model.dart`: Verdict, Check, Claim, Challenge with defensive `fromJson` (fallback extractor for the first `{...}` block).
5. `features/verification/verifier_service.dart`: pipeline
   `prepare evidence → fetch/verify links → build prompt → route model (vision swap if screenshot) → complete() JSON → parse →
   enforce code-side rules (confidence < 0.7 ⇒ partial; non-2xx URL evidence ⇒ fail) → cross-check claims against fetched text →
   mark each source Verified / Reachable / Dead`.
   Emit progress events (`ReadingEvidence`, `FetchingSources`, `CrossChecking`, `WritingVerdict`) through a Stream for the UI.
6. **Verification screen**:
   - Animated step list (spinner → path-drawn checkmark).
   - Source card strip (favicon, domain, title, status chip) staggering in; dead links shake then dim.
   - Streaming summary text with tappable inline `[n]` citation pills that pulse the matching card.
   - Provider/model chip on the result and a "rerouted via X" chip if fallback happened.
7. Wire phase 3's submit button to the real service. A `pass` verdict completes the task (animation in phase 6; for now a simple state change).
8. Failure handling: any `AiFailure` yields an in-character message and a retry button, never a stack trace.

## Exit criteria
- Real run with a good public URL ⇒ `pass` with Verified sources.
- A dead link ⇒ forced `fail` and the dead-link card appears.
- A vision model reads a screenshot (test with a real screenshot).
- `flutter analyze` clean. Commit: "phase 4: verification agent and sources".
- Update docs, `features/verification/README.md`, and `docs/AI_USAGE.md`.
