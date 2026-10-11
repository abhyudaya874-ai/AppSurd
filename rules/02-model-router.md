# 02 — Model Router and the Pill Model Selector (SIGNATURE FEATURE)

This is the most important UI in the app. Spend polish time here first.

## Providers (all OpenAI-compatible `/chat/completions`, so ONE client class with a base URL + key)
| Provider   | Base URL                              | Key source            |
|------------|----------------------------------------|-----------------------|
| Groq       | `https://api.groq.com/openai/v1`       | user-entered / define |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1`  | user-entered / define |
| OpenRouter | `https://openrouter.ai/api/v1`         | user-entered / define |

Implement `OpenAiCompatClient(baseUrl, apiKey, extraHeaders)` with:
- `Future<String> complete(...)` for non-streaming JSON calls (verdicts).
- `Stream<String> stream(...)` for SSE token streaming (answer text). Parse `data:` lines, stop on `[DONE]`.
- OpenRouter extra headers: `HTTP-Referer` and `X-Title` (app name).

## Model catalog = config, not code
All models live in ONE file: `core/ai/model_catalog.dart`, as a const list of:
```dart
ModelSpec(
  id: 'provider-specific-model-id',
  provider: Provider.groq,
  displayName: 'Llama 70B',
  tier: Tier.balanced,        // swift | balanced | smart | deep
  strength: 0.0..1.0,         // used for slider ordering
  supportsVision: false,
  supportsReasoning: false,
  blurb: 'for balanced everyday tasks',
)
```
**Model IDs change often.** Do NOT trust remembered IDs. On first run (and from a "Refresh models" action) call each
provider's `GET /models` endpoint, intersect with the catalog, and drop entries that no longer exist. If a tier ends up
empty, fall back to the nearest tier. Prefer free or low-cost models for the demo.

Suggested tier layout (pick whatever currently exists on each provider):
- **Swift**: smallest fast model, Groq preferred (lowest latency).
- **Balanced**: ~70B class general model, Groq or NVIDIA.
- **Smart**: strongest non-reasoning model available on NVIDIA or OpenRouter.
- **Deep**: a reasoning-capable model on OpenRouter (or NVIDIA), used with higher reasoning effort.
- Keep at least one **vision-capable** model reachable per tier from Balanced up (screenshots are evidence).

## Router behavior
- `ModelRouter.pick(Task task, Preset preset, Overrides? custom) -> ModelSpec`.
- Preset slider selects a tier; within a tier choose the highest-`strength` model whose provider has a key configured.
- If the evidence is an image and the chosen model lacks vision, silently swap to the nearest vision-capable model
  and show a small animated chip: "Switched to <model> to read your screenshot".
- **Auto fallback chain**: on 429/5xx/timeout, retry once on the next provider in the same tier, then drop a tier.
  Surface this in the UI as a subtle "rerouted via <provider>" chip — it is a demo highlight.
- Providers without a key are shown dimmed with a lock-style affordance and a tap target that opens Settings.

## The pill selector (UI spec — described in text; do not rely on screenshots)
Reference pattern: Perplexity's composer model control. Recreate the *interaction*, with our own visual identity.

**Collapsed state**
- A pill-shaped chip in the composer row (height ~40, fully rounded, glass/tonal surface).
- Contents: provider glyph (small monogram circle, tinted per provider) + model display name + preset label in lighter
  weight (e.g. "Llama 70B  Balanced") + chevron. Left of label: 3–5 tiny strength dots reflecting the current tier.
- Changing selection cross-fades the label (AnimatedSwitcher with slide+fade) and the pill width animates smoothly
  to fit (AnimatedSize / measured width tween). No jumps.

**Expanded state (opens on tap)**
- The pill morphs into a floating card anchored above/below it (OverlayEntry + CompositedTransformFollower,
  with a shared-element feel: the pill's rounded rect grows into the card, ~320 ms, `easeOutCubic` / spring).
- Card header: model name + one-line blurb, e.g. "<Model> for balanced reasoning and cost." This text
  cross-fades as the slider moves.
- **Strength slider** (custom-painted, NOT the stock Slider):
  - 4 detents: Swift, Balanced, Smart, Deep. Track has dots at each detent.
  - Thumb stretches horizontally while dragged (squash and stretch), snaps to nearest detent with a spring on release,
    fires `HapticFeedback.selectionClick()` on every detent crossing.
  - The filled part of the track animates in a gradient that shifts hue from the Swift provider tint to the Deep tint.
  - Labels under the track brighten for the active stop.
- Under the slider: a **Custom ›** row. Tapping it slides in a sub-panel with three rows:
  - **Model** → list of all catalog models grouped by provider (provider headers, strength dots, vision/reasoning badges).
  - **Reasoning** → Low / Medium / High (maps to `reasoning_effort` / OpenRouter `reasoning.effort` where supported; hidden if unsupported).
  - **Speed** → Normal / Fast (Fast biases routing toward the lowest-latency provider, i.e. Groq).
  - A "Return to presets" row collapses back to the slider.
- Dismiss by tapping outside or dragging down; reverse animation morphs the card back into the pill.

**State**: `modelSelectionProvider` (Notifier) holds `{preset, customModelId?, reasoning, speed}`; persist to Hive.
The selected model is shown on every AI message bubble as a tiny provider chip so judges can see routing in action.

## Acceptance checks
- Dragging the slider updates the pill label live and never drops below 60 fps on a mid-range phone.
- Switching preset changes which provider/model is actually called (log it in debug builds).
- With only ONE provider key set, the app still works and the other providers appear dimmed, not broken.
