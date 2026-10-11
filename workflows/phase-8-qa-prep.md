# Phase 8 — Q&A Preparation (budget: 10 min)

Judges test whether the team understands the AI-written code. Inexplicable logic costs heavy Process marks.

## Steps
1. Read the whole codebase and write `docs/QA_CHEATSHEET.md` with 25+ likely questions and 2–3 sentence answers in plain language. Must include:
   - Why Riverpod? Why dio instead of http? Why one OpenAI-compatible client for three providers?
   - How does the router choose a model? What happens on a 429? How does vision fallback work?
   - How is the pill slider built (CustomPainter, detents, spring, haptics)?
   - How do we guarantee links are real? What is the difference between Verified, Reachable, and Dead?
   - How is the verdict parsed defensively? Why is the pass threshold enforced in code, not by the model?
   - How is prompt injection handled? Where do API keys live? What is in Demo Mode?
   - Walk through the data flow from "Submit proof" to "task completed".
2. For each of the 10 most complex files, add a "Read this first" 5-line header comment (purpose, inputs, outputs, gotchas).
3. Create `docs/WHO_OWNS_WHAT.md` mapping each feature folder to a team member so each person can speak for their part.
4. Produce a 60-second "explain the architecture" speech for each team member.

## Exit criteria
- Every team member can open any file listed in the cheatsheet and explain it. Commit: "phase 8: Q&A prep".
