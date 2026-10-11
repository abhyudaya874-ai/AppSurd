# Dependencies — Receipts

Every third-party package and external API, one line each (required for the
hackathon disclosure).

## Packages

| Package | Why |
|---|---|
| flutter_riverpod | State management (Notifier/AsyncNotifier) — mandated stack |
| dio | HTTP client with SSE streaming support for AI responses |
| hive_ce, hive_ce_flutter | Local persistence for tasks, chat, model selection |
| flutter_secure_storage | API keys entered in-app live here, never in plain files |
| flutter_animate | Staggered/declarative animation helpers |
| google_fonts | Inter (body) + Space Grotesk (display) |
| flutter_markdown_plus | Renders streamed AI verdict text (maintained fork of flutter_markdown) |
| url_launcher | Opens verified sources in the external browser |
| image_picker | Screenshot evidence capture |
| confetti | Pass-verdict celebration burst |
| html | Strips fetched pages to readable text for the verifier |

## External APIs

| API | Use |
|---|---|
| Groq `api.groq.com/openai/v1` | Fast chat models (Swift/Balanced tiers) |
| NVIDIA NIM `integrate.api.nvidia.com/v1` | Stronger models (Balanced/Smart/Deep) |
| OpenRouter `openrouter.ai/api/v1` | Reasoning models + optional web plugin |
| GitHub REST `api.github.com` | Commit evidence fetching (public, unauthenticated) |
| Google favicons `google.com/s2/favicons` | Source-card icons |

## Boilerplate

`flutter create` scaffold only (platform folders, launcher icons, lints).
