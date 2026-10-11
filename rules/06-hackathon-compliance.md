# 06 — Hackathon Compliance and Q&A Readiness

These rules protect the team from disqualification and from the Process (25 marks) deductions.

## Fresh development
- All project code is written inside the official window (11 Oct 2026, 1:00–6:30 PM IST). Do not import code, templates, or
  prior projects. `flutter create` boilerplate is allowed but must be listed as "basic boilerplate" in the disclosure.
- Do not copy code from other teams or from existing repos. Using documented package APIs is fine.

## Disclosure (keep these files current as you build)
- `docs/DEPENDENCIES.md`: every third-party package and public API (Groq, NVIDIA NIM, OpenRouter, GitHub REST API, favicon service), one line each.
- `docs/AI_USAGE.md`: running log of how AI was used (which tool, for what, what was reviewed/changed by humans).
  At the end it is condensed into the **150–200 word AI Usage Declaration** (see phase 7). Keep it honest; do not overclaim human authorship.

## Explainability (the team must be able to explain every line)
- Prefer simple, direct code over clever abstractions. No code generation, no meta-programming, no deep inheritance.
- Each feature folder gets a short `README.md` (5–10 lines): what it does, the data flow, the 2–3 key classes.
- After each phase, update `docs/ARCHITECTURE.md` with a plain-language data-flow diagram in text/mermaid.
- Comment the *why* of non-obvious decisions (router fallback, link verification, JSON defensive parsing, animation math).
- Maintain `docs/QA_CHEATSHEET.md`: 20+ likely judge questions with 2–3 sentence answers (see phase 8).

## Demo safety
- Ship a **Demo Mode** toggle in Settings: pre-seeded tasks plus canned example evidence (one good URL, one weak screenshot, one lazy text)
  so the pitch works if Wi-Fi or an API fails. The canned path must still run the real UI and animations.
- Keep a debug-only "force verdict" action out of release builds, or clearly labelled Demo Mode only. Do not fake AI results silently.
- Never display fabricated sources as real. Demo Mode content is labelled "Demo data".

## Submission deliverables checklist
1. Public GitHub repo link (no secrets in history).
2. Runnable build: `app-release.apk` (primary). Optional Flutter Web URL.
3. Slide deck PDF/PPT.
4. AI Usage Declaration, 150–200 words.
Pitch: 3–5 minutes live demo + 2–3 minutes Q&A. Stay inside the time limit.
