# Who Owns What

Fill in names; the 60-second version each owner can give is sketched under
their column.

| Area | Owner | Files |
| --- | --- | --- |
| Product + verification pipeline | [name] | `features/verification/`, `core/net/`, `core/ai/prompts.dart` |
| Model router + pill | [name] | `core/ai/model_router.dart`, `features/model_picker/`, `core/ai/` |
| Tasks + evidence + accountability | [name] | `features/tasks/`, `features/accountability/` |
| Theme, motion, app shell | [name] | `core/theme/`, `core/widgets/`, `app.dart`, `features/splash/` |

## 60-second explanations

**Verification owner:**
"Evidence goes into `VerifierService.verify` as a stream — we fetch every
link ourselves with dio before the model sees anything, so a URL is
'verified' because *we* loaded it, not because the model says so. The model
returns strict JSON; we parse it defensively, enforce the confidence floor
in code, and dead evidence forces a fail without a model call at all."

**Router/pill owner:**
"The pill is the router's UI. Four detents map to tiers; `plan()` filters
the catalog by tier, keys, live `/models`, and vision needs, then
`execute()` walks the candidates — same-tier provider first, then drop a
tier. Whatever answered shows up as a chip on the verdict. The slider thumb
is a custom painter with a spring simulation — it's the part of the app
people remember touching."

**Tasks/accountability owner:**
"Tasks are immutable models in a Hive box; there is no 'complete' action —
status moves only through verdicts and challenges. Weak evidence writes a
lock + a challenge onto the attempt; the countdown ring drives retype, quiz,
or reupload. Integrity is derived state: base 50, +10 pass, −5 fail, +2 for
finishing the challenge fast."

**Theme/motion owner:**
"Everything visual runs through tokens — spacing, durations, provider tints
are ThemeData extensions, so there's nothing to hunt for. Motion: fast 150,
base 260, slow 420, hero 520 with a shared spring spec; reduced-motion
collapses it all in `didChangeDependencies`. Widgets never hardcode a color
or a millisecond."
