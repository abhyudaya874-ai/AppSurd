# 05 — API Keys, Security, and Safety

## Keys
- **Never commit API keys.** The GitHub repo must be public for submission.
- `.gitignore` must include `env.json`, `*.env`, `.env*`, `android/key.properties`, and any local debug logs. Create it in the scaffold step.
- Two supported ways to provide keys (implement both):
  1. **In-app Settings screen** — user pastes a key per provider; stored with `flutter_secure_storage`; "Test key" button calls `GET /models` and shows success/failure with animation.
  2. **Build-time** `--dart-define-from-file=env.json` with `GROQ_API_KEY`, `NVIDIA_API_KEY`, `OPENROUTER_API_KEY`
     (read via `String.fromEnvironment`). Provide `env.example.json` with empty values.
- Keys are never logged, never shown in error messages, never sent anywhere except their own provider's base URL.
- Remember: keys baked into an APK are extractable. For the demo APK use throwaway/limited keys and revoke them after the event.

## Network
- Timeouts everywhere (connect 8 s, receive 30 s; streams 60 s).
- Every provider call wrapped in a typed `AiFailure` (auth, rate-limit, network, bad-response) so the UI can show a friendly in-character message.
- Android: add `INTERNET` permission; image picking needs no extra permission with `image_picker` on modern Android.

## Safety of content
- Roasts target the *evidence*, never the person's identity or attributes. No profanity, no harassment.
- Challenges must be harmless, quick, and cognitive/typing based. No physical or risky challenges.
- Treat all fetched web content and user evidence as untrusted input (prompt-injection defence, see `03-verification-agent.md`).
- Do not store or transmit user data anywhere except to the chosen AI provider for verification. State this in Settings → About.
