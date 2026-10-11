# Dependencies

| Package | Why |
| --- | --- |
| flutter_riverpod | Feature state — notifiers/providers, no codegen needed. |
| dio | HTTP for provider calls, link fetching, GitHub REST. Typed timeouts, redirects, interceptable. |
| hive_ce + hive_ce_flutter | Local persistence for tasks, settings, model selection. No codegen via Map<String,dynamic> storage. |
| flutter_secure_storage | API keys — Android Keystore backed, never Hive/shared-prefs. |
| google_fonts | Inter + Space Grotesk — fonts are BUNDLED in assets/fonts (runtime fetching disabled, offline-proof). |
| flutter_animate | Available for chained animations (kept light — most motion is hand-rolled for explainability). |
| confetti | Pass-verdict celebration. |
| image_picker | Screenshot evidence capture, downscaled ≤1280px at source. |
| html | Strip fetched pages to title/meta/visible text. |
| flutter_markdown_plus | Verdict/answer rendering (maintained fork of flutter_markdown). |
| url_launcher | Open sources in browser. |
| uuid | Task/attempt ids. |
| intl | Timestamp formatting. |
| cupertino_icons | Scaffold stock. |

## Versions
Pinned to latest stable at build time (October 2026). `flutter pub outdated`
warns about majors we intentionally skip mid-hackathon.
