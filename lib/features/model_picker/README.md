# Model Picker — the pill selector

Signature feature. A collapsed pill in the composer that morphs into a
floating card with a strength slider.

## Data flow
`modelSelectionProvider` (Notifier, persisted to Hive box `receipts_settings`)
holds `{preset, customModelId, reasoning, speed}`. `resolvedModelProvider`
runs `ModelRouter.plan()` on that selection + configured keys + the live
`aliveModelsProvider` list so the pill always shows what would actually
answer.

## Key classes
- `ModelPill` — collapsed chip; owns the `OverlayEntry` + morph controller.
- `ModelPickerOverlay` — scrim + anchored card that grows from the pill rect;
  clamps inside the screen and above the keyboard; outside-tap or drag-down
  dismisses.
- `StrengthSlider` — custom-painted, 4 detents, stretching thumb, spring
  snap, haptic per detent; gradient fill colored per-tier provider tints.
- `CustomPanel` — model list grouped by provider (locked providers dimmed),
  reasoning effort, speed bias, "return to presets".
