# AI Declaration

This app was built during AppSurd'26 by our team with **Devin (SWE-2 Max)** as
the primary implementation partner, working from a written spec in
`rules/` + `workflows/` that the team authored before coding began.

**What the AI did:** scaffolded the Flutter project; implemented the theme,
motion system, model catalog/router, pill selector, task/evidence layer,
verification pipeline, roast/challenge loop, docs, and tests; ran
`flutter analyze` / `flutter test` / debug builds after each phase; and fixed
real bugs it introduced (a `MediaQuery`-in-`initState` crash, font fetching,
null extension access) by reproducing, tracing, and verifying fixes.

**What humans did:** chose the product concept and verification-driven UX;
wrote the phase plan and rules the AI executed; picked the provider set
(Groq / NVIDIA NIM / OpenRouter); reviewed output and drive-tested the app on
a physical device; and own final judgment on roasts, copy, and ethics.

**Model used for the build:** SWE-2 Max via the Devin CLI. **Models used at
runtime:** whichever catalog model the router selects per request — the app
never hides which model answered. **Arena mode** fans one evidence pack out
to a 2–4-model jury; verdict aggregation is computed in Dart (weighted vote,
strictness floor), never delegated. **Voice:** whisper.cpp runs on-device via
`whisper_flutter_new` (tiny model downloaded at runtime from HuggingFace —
disclosed third-party asset, never bundled); speech_to_text and Groq's hosted
Whisper are labelled fallbacks; roast read-aloud uses flutter_tts.

All code was written fresh for this event; nothing was copied from other
projects.
