# Tasks + Evidence

Proof-gated tasks: there is no "mark complete" — a task completes only via a
`pass` verdict from the verification pipeline.

## Data flow
`TasksNotifier` (AsyncNotifier) persists `Task` objects as JSON maps in the
`receipts_tasks` Hive box. `Task.attempts` holds every `EvidenceAttempt`
(url / screenshot / text / commit) with its parsed verdict JSON.
`integrityScoreProvider` derives the score from per-task `integrityDelta`.

## Key classes
- `Task` / `EvidenceAttempt` — immutable models, hand-written JSON.
- `TaskListScreen` — staggered list, swipe-to-delete, integrity chip.
- `AddTaskSheet` — title + "what counts as proof?" hint.
- `TaskDetailScreen` — Hero from card; attempts history; Submit proof.
- `EvidenceSheet` — segmented control (URL/shot/text/commit) with sliding
  indicator; inputs validate before creating an attempt.
