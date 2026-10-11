# Phase 2 — Model Router and the Pill Selector (budget: 50 min)

Follow `.devin/rules/02-model-router.md` exactly. This is the signature feature.

## Steps
1. `core/ai/openai_compat_client.dart`: one client class (base URL, key, extra headers) with `complete()` and `stream()` (SSE parsing).
2. `core/ai/model_catalog.dart`: `Provider`, `Tier`, `ModelSpec`, and the const catalog. Fetch each provider's `GET /models` to confirm
   which catalog IDs still exist; never rely on remembered model IDs.
3. `core/ai/model_router.dart`: `pick()`, vision swap, fallback chain (retry next provider in tier, then drop a tier), speed bias.
4. `features/settings/`: API keys screen (secure storage, "Test key" button with animated result), plus `--dart-define` fallback.
5. `features/model_picker/`:
   - `model_selection_provider.dart` (Notifier, persisted to Hive).
   - `model_pill.dart` (collapsed pill with AnimatedSwitcher label, strength dots, provider glyph).
   - `model_picker_overlay.dart` (morphing overlay card, outside-tap/drag-down dismiss).
   - `strength_slider.dart` (custom painted: 4 detents, stretching thumb, spring snap, haptics, gradient fill).
   - `custom_panel.dart` (Model list grouped by provider, Reasoning, Speed, "Return to presets").
6. Build a temporary **playground screen**: composer with the pill, a text field, and a send button that streams a reply from the selected model
   with a provider chip on the bubble. This proves routing works before the task features exist.
7. Log (debug only) which provider/model each call used.

## Exit criteria
- Slider drag is smooth (profile mode), label morphs without jumps, haptics fire per detent.
- Changing presets demonstrably changes the provider/model that answers.
- App works with only one key configured; missing providers appear dimmed.
- `flutter analyze` clean. Commit: "phase 2: model router and pill selector".
- Update `docs/ARCHITECTURE.md`, `docs/AI_USAGE.md`, and `features/model_picker/README.md`.
