# Receipts

**Add a task. Submit evidence. Get verified — or get roasted.**

AppSurd'26 hackathon: *Verification-Driven Productivity Agent*.

A task in Receipts can't be marked "done" — it has to be **proved**. You
submit evidence (a URL, a screenshot, a written claim, or a GitHub commit),
an AI verifier checks it against the task, fetches your links itself, and
returns a verdict with real sources. Weak evidence gets you a
passive-aggressive roast and a timed accountability challenge before you can
try again.

```
add task → submit evidence → AI verdict with sources → roast/challenge or complete
```

## The three requirements, visibly

1. **Evidence required** — there is no "mark complete". Tasks reach `done`
   only through a `pass` verdict.
2. **AI verification** — an OpenAI-compatible model (Groq / NVIDIA NIM /
   OpenRouter) scores evidence. The app fetches every link itself — sources
   are *Verified* only when our own fetch got 2xx **and** the fetched text
   backs a claim. Dead links are shown struck-through, never hidden.
3. **Roast + accountability** — `partial`/`fail` shows a styled roast card
   (local bank fallback if offline), locks the task, and issues a timed
   challenge: retype, quiz, or reupload. Finish it to unlock.

## Signature interaction

The **model pill** (top of the task list): a collapsed chip showing provider +
model + preset + strength dots. Tapping morphs it into a floating card with a
custom-painted strength slider — 4 detents (Swift / Balanced / Smart / Deep),
thumb stretches while dragging, spring-snaps on release, haptic at each
crossing. The router behind it picks the strongest keyed model in the tier,
retries across providers on 429/5xx/timeouts, drops a tier on sustained
failure, and auto-swaps to a vision model when you submit a screenshot.

## Architecture (30 seconds)

```
Task (Hive) ──► EvidenceSheet ──► VerifierService.stream
                                     ├─ LinkVerifier  (real GET, 8s, ≤200KB)
                                     ├─ GitHubClient  (commit/PR via REST)
                                     └─ ModelRouter   (tier → provider candidates)
                                   verdict JSON ──► pass/partial/fail
                                   fail ──► roast + locked + challenge
```

Feature-first `lib/features/*`, shared infra in `lib/core/*`. State is
Riverpod notifiers; styling lives in ThemeData + tokens; no codegen, no
backend, no login.

## Run

```bash
flutter pub get
cp env.example.json env.json   # add at least one provider key
flutter build apk --release --dart-define-from-file=env.json
# or debug: flutter run
```

Keys also work from **Settings → API keys** at runtime (secure storage).
No key? The app still verifies — a labelled `[demo verdict]` judges the
fetches it really made.

## Repo map

| Path | What |
| --- | --- |
| `lib/core/ai/model_router.dart` | tier selection, failover, vision swap |
| `lib/features/verification/` | pipeline events, verdict model, Perplexity-style screen |
| `lib/features/model_picker/` | pill, morph overlay, custom slider |
| `lib/features/accountability/` | roast bank/card, countdown ring, challenges |
| `docs/` | architecture, dependencies, AI usage log, declaration, pitch |
| `rules/`, `workflows/` | the spec this was built to |

Tested: `flutter analyze` clean, `flutter test` 13/13, on-device Android.
