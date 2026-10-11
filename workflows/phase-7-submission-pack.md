# Phase 7 — Submission Pack (budget: 20 min; start at least 30 min before the end)

## Steps
1. **Secrets audit**: search the repo and full git history for any API key patterns (`gsk_`, `nvapi-`, `sk-or-`). Remove from tracked files;
   if any ever reached a commit, rotate that key and rewrite history before pushing. Confirm `.gitignore` covers `env.json`.
2. **Release build**: `flutter build apk --release` (use `--dart-define-from-file=env.json` with throwaway demo keys). Install on a phone and run the full demo path once.
   Copy the APK to `build_outputs/receipts.apk` (not committed if large; upload to Drive/Release instead).
3. **README.md** at repo root: what it is, GIF/screenshots placeholders, features (evidence → verify → sources → roast → challenge, pill selector),
   setup (`flutter pub get`, `env.example.json`), how routing works, tech stack, disclosure of packages/APIs.
4. **docs/AI_USAGE.md** finalised and condensed into the **AI Usage Declaration (150–200 words)** saved as `docs/AI_DECLARATION.md`.
   Cover: tools used (Devin, plus any chat assistants), what they generated, what the team reviewed/rewrote/tested,
   the in-app AI use (Groq / NVIDIA NIM / OpenRouter models for verification), and safeguards (verified links only, untrusted-input handling).
   Count the words; stay between 150 and 200.
5. **Slide deck outline** in `docs/PITCH_OUTLINE.md` (8–10 slides, the team turns it into PDF/PPT): problem, idea, demo flow,
   how verification works, verified sources, the pill selector and routing, roast + accountability, architecture, AI workflow, what's next.
6. **Pitch script** in `docs/PITCH_SCRIPT.md`: a timed 4-minute live demo plan hitting all three prompt requirements and the pill selector, plus a Demo Mode fallback.
7. Final checks: `flutter analyze`, `flutter build apk --release`, public repo visible, link works in a private window.

## Exit criteria
- Repo link, APK link, slide deck, and declaration all ready to paste into the submission form.
- Commit: "phase 7: submission pack".
