# Phase 1 — Scaffold and Theme (budget: 20 min)

Read all of `.devin/rules/` first.

## Steps
1. `flutter create --org com.receipts --platforms android,web receipts` (or use the existing repo root). Remove the counter demo.
2. Add dependencies from `01-flutter-architecture.md`: flutter_riverpod, dio, hive_ce, hive_ce_flutter, flutter_secure_storage,
   flutter_animate, google_fonts, flutter_markdown, url_launcher, image_picker, confetti, html (for text extraction).
3. Create the folder structure from `01-flutter-architecture.md` with empty placeholder files only where needed.
4. Create `.gitignore` additions and `env.example.json` per `05-security-and-keys.md`.
5. Implement `core/theme/`: color tokens (dark-first + light), typography (Inter + display font), `motion.dart` tokens, ThemeData.
6. Implement shared widgets: `Pressable` (scale-on-press spring), `FadeSlideIn` (staggered entrance helper), `ShimmerBox`.
7. `app.dart` + `main.dart`: ProviderScope, Hive init, theme, a splash that animates the logo mark in and then routes to a placeholder Home.
8. Create `docs/ARCHITECTURE.md`, `docs/DEPENDENCIES.md`, `docs/AI_USAGE.md` with the first entries.
9. Add Android `INTERNET` permission.

## Exit criteria
- `flutter analyze` clean, `flutter build apk --debug` succeeds, app launches with the animated splash on a device/emulator.
- Commit: "phase 1: scaffold, theme, motion tokens".
