# Phase 3 — Tasks and Evidence Capture (budget: 40 min)

## Steps
1. `features/tasks/task_model.dart`: `Task { id, title, description, createdAt, status(open|verifying|locked|done), attempts[], integrityDelta }`
   and `EvidenceAttempt { type, payload, submittedAt, verdict? }`. Hand-written JSON, Hive adapters via simple JSON maps (no codegen).
2. `tasks_provider.dart`: AsyncNotifier with add / delete / update / persist.
3. **Task list screen**: animated list (stagger in, `AnimatedList` for add/remove), swipe-to-delete with spring-back,
   empty state with a small looping animation, an Integrity Score header chip.
4. **Add task**: bottom sheet that slides up with a spring; title + optional "what counts as proof?" field.
5. **Task detail** (Hero from the card): shows the task, its attempts history, and a prominent **Submit proof** button.
   There is NO plain "Mark complete" anywhere in the UI. Completion only happens via a `pass` verdict.
6. **Evidence capture sheet**: segmented control with sliding indicator for URL / Screenshot / Text / Commit;
   per-type input (URL validation, `image_picker` with downscale to ≤1280 px, multiline text with character counter,
   commit URL parser for `github.com/{owner}/{repo}/commit/{sha}`). Switching types uses size-aware `AnimatedSwitcher`.
7. A **Demo Mode** switch in Settings that seeds three tasks (see `06-hackathon-compliance.md`).
8. The submit button is wired to a stub `VerificationService.verify(task, evidence)` returning a fake pending state
   (real implementation arrives in phase 4).

## Exit criteria
- Add, view, delete tasks; capture all four evidence types; persistence survives app restart.
- `flutter analyze` clean. Commit: "phase 3: tasks and evidence capture".
- Update docs and `features/tasks/README.md`.
