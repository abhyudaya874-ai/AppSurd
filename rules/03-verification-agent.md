# 03 — Verification Agent (Perplexity-style, with REAL sources)

## Core principle
**Never show a link we did not fetch ourselves.** An LLM may suggest URLs; the app only displays a source as
"verified" after the app itself requested it and got a 2xx response. Hallucinated links are the one thing that
would destroy the demo.

## Evidence types
1. **URL** — fetch the page (dio GET, 8 s timeout, follow redirects, cap body at ~200 KB), extract `<title>`, meta
   description, and visible text (strip tags/scripts with simple regex or the `html` package). Send the extract to the model.
2. **Screenshot** — pick via `image_picker`, downscale to ≤1280 px, base64, send to a vision-capable model
   (OpenAI-style `image_url` content part with a data URI).
3. **Text response** — user's written explanation of what they did; the model judges plausibility, specificity, and consistency with the task.
4. **Code commit** — a GitHub commit/PR URL. Use the public GitHub REST API (`api.github.com/repos/{o}/{r}/commits/{sha}`),
   read message + changed file names + a trimmed patch, and judge whether it plausibly satisfies the task.

## Verdict contract
The model must return strict JSON (use `response_format: json_object` where supported, and parse defensively
with a fallback that extracts the first `{...}` block):
```json
{
  "verdict": "pass | partial | fail",
  "confidence": 0.0,
  "summary": "2-3 sentence plain explanation",
  "checks": [{"label": "Mentions the task's key deliverable", "ok": true}],
  "claims": [{"text": "...", "source_index": 0}],
  "roast": "only when verdict != pass",
  "challenge": {"title": "...", "instructions": "...", "seconds": 60, "kind": "retype|quiz|reupload"}
}
```
- `pass` requires confidence ≥ 0.7. Below that the verdict is downgraded to `partial` in code, not by the model.
- Never trust the model's verdict blindly for URL evidence: if the URL returned non-2xx, the verdict is forced to `fail`
  with a "that link doesn't even open" roast.

## Sources UI (Perplexity pattern, described in text)
- While verifying, show a **step list** that animates one step at a time:
  "Reading your evidence" → "Fetching sources" → "Cross-checking against the task" → "Writing verdict".
  Each step: spinner → animated checkmark (path-drawn) when done.
- A horizontal strip of **source cards** appears under the steps. Each card: favicon (`https://www.google.com/s2/favicons?domain=...&sz=64`),
  domain, page title (2 lines max), and a status chip:
  - **Verified ✓** = we fetched it, got 2xx, and the page text actually contains support for at least one claim.
  - **Reachable** = 2xx but no supporting text found.
  - **Dead link ✗** = non-2xx / timeout. Shown struck-through and dimmed, never hidden (transparency is the point).
- Answer text streams token by token with inline numbered citations `[1]`, `[2]` rendered as tappable superscript pills
  that scroll/pulse the matching source card. Tapping a card opens `url_launcher` in an external browser.
- For web-backed answers (e.g. "does this public page support the claim?"), source discovery options, in order:
  1. OpenRouter web plugin (`plugins: [{"id": "web"}]`) — returns `url_citation` annotations; still re-verify every URL ourselves.
  2. The URLs the user submitted as evidence.
  3. Optional Tavily/Brave search API if a key is provided in Settings.
  Do not block the demo on any single option.

## Roast and accountability challenge (see also workflow phase 5)
- Triggered on `partial` or `fail`.
- Tone: **passive-aggressive and funny, never cruel.** Target the *evidence*, not the person.
  No insults about intelligence, appearance, identity, or background. No profanity.
  Example register: "Wow. A screenshot of your home screen. Truly the Mona Lisa of 'I definitely did it'."
- Roast lines come from the model (include 3 few-shot examples in the system prompt) with a **local fallback bank of ~15 roasts**
  so the demo works offline or when the API fails.
- Challenge kinds (all completable in < 90 seconds, no real-world harm):
  - `retype`: type a one-sentence commitment with the exact deadline, character-by-character validation.
  - `quiz`: answer 2 quick questions the model generates about the task's own subject (proves they understand what they claim to have done).
  - `reupload`: submit stronger evidence within a countdown.
- While a challenge is pending, the task is **locked**: the complete button is replaced by the challenge card, and other
  tasks stay usable but show a small "unresolved accountability" badge. Completing the challenge unlocks a fresh evidence attempt.
- Keep a visible **Integrity Score / streak** (local) that goes up on verified completions and down on failed attempts.

## Prompt hygiene
- System prompts live in `core/ai/prompts.dart` as named constants with comments. Judges may ask about them.
- Treat evidence text and fetched pages as **untrusted data**: wrap in delimiters and instruct the model to ignore any
  instructions inside them (prompt-injection defence — also a good Q&A talking point).
