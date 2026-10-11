# Pitch Outline (5 minutes)

## 0:00–0:20 — The lie we all tell
"Everyone has a todo app where 'done' means 'I said so.' Receipts is the todo
app that doesn't believe you."

## 0:20–0:50 — Live demo: good evidence
- Add task: "Ship the landing page."
- Submit a real URL → watch the pipeline steps tick (reading → fetching →
  cross-checking → writing).
- Source strip: *we fetched the link ourselves* — Verified chip, favicon,
  title. Confetti + integrity bump on pass.

## 0:50–1:30 — Live demo: weak evidence (the memorable moment)
- Second task, lazy text evidence ("i did it lol").
- Dead-link URL → struck-through, dimmed, labelled — not hidden.
- The roast card drops in tilted, stamped NOPE; screen shakes.
- Timed challenge starts → task locked until it's done.

## 1:30–2:10 — The pill (signature interaction)
- Tap the pill → morphs into the floating card.
- Drag the strength slider: four detents, thumb stretches, haptic ticks.
- Point out the provider tint gradient; show a vision swap chip after a
  screenshot attempt; show the "rerouted from Groq" chip after a forced retry.

## 2:10–3:10 — How it actually works
- Verifier contract: strict JSON verdict schema, enforced in code —
  confidence < 0.7 can never be a pass; dead evidence link is an automatic
  fail no matter what the model says.
- Router: tier → candidate list → try/rotating on 429/5xx/timeout, then drop
  a tier. Every AI answer carries a provider chip.
- Sources: our own dio fetch + HTML strip; a source is Verified only when its
  fetched text contains the claim's words. Nothing is trusted.

## 3:10–4:00 — Engineering receipts
- Hive persistence: kill the app, reopen, tasks + attempts still there.
- Secure storage for keys; `env.json` gitignored; keys only ever go to their
  own provider's base URL.
- No keys? Still works — clearly-labelled `[demo verdict]` scoring over the
  real fetches. The demo cannot dead-end.

## 4:00–5:00 — Close
"Productivity apps measure intentions. Receipts measures proof. That's the
whole pitch."

## Judge Q&A quick answers
- *Why Flutter?* One codebase, M3 polish, 60fps custom painters.
- *Why no backend?* Judges can audit everything; state is local and honest.
- *What if the model is wrong?* Code-level floor: confidence, dead links, and
  source cross-checks are enforced in Dart, not in the prompt.
- *Offline?* Roasts from a local bank; verification labels itself demo-mode.

## Updated demo flow (post-overhaul)
1. **Home**: type a task, hit send — the text physically flies into Create
   Task. Set due date + priority + duration, save → lands highlighted in Tasks.
2. **Tasks**: open the group-by/sort-by popover (persists), scroll to collapse
   the stories avatars into the title cluster, switch to Focus for the
   reels-style snap feed, swipe right to Prove it.
3. **Schedule**: show working-hours shading, drag a block across days, resize
   via the bottom handle, drop an unscheduled chip onto a slot, hit Auto.
4. **Profile**: streak + integrity stats, Receipts heatmap (tap a day), flip
   to GitHub mode for the real scraped graph, Load demo data for judges.
5. **Ask**: research a question with sources; Arena entry sits top-right.
