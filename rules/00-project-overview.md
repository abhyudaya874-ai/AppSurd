# 00 — Project Overview (always apply)

## What we are building
**Receipts** (working title): a Flutter task manager where a task can only be marked complete after the
user submits **evidence**. An AI agent verifies the evidence and shows its reasoning Perplexity-style,
with **real, fetched, verified source links**.

If evidence is weak, the agent replies with a **humorous passive-aggressive roast** and issues a
**lightweight accountability challenge** the user must finish before they can make further progress.

## Hackathon context (AppSurd'26, IIT ISM Dhanbad)
- Flutter ONLY. No React Native, KMP, or native-only code.
- Dev window: 11 Oct 2026, 1:00 PM – 6:30 PM IST. Submission window opens ~15 min before the end.
- Assigned mystery prompt: **Verification-Driven Productivity Agent**.
- Judged on: Product 25, Prompt Interpretation 25, Presentation 25, Process 25.
  - Prompt Interpretation: deliver all three parts of the prompt visibly —
    (1) evidence required to complete a task, (2) AI verification of that evidence,
    (3) passive-aggressive reply + accountability challenge when evidence is insufficient.
  - Process: the team must explain every line of AI-written code in Q&A (see `06-hackathon-compliance.md`).

## Priorities (in this order)
1. A working end-to-end demo path: add task → submit evidence → AI verdict with sources → roast/challenge or complete.
2. The **pill-shaped model selector with strength slider** (see `02-model-router.md`). This is the signature feature.
3. Animation and transition quality (see `04-animation-motion.md`).
4. Everything else.

Never sacrifice (1) for (3). The app must run on a physical Android device or emulator at every phase boundary.

## Non-goals
No login/accounts, no backend server, no cloud sync, no push notifications, no payments, no multi-user.
All state is local. All AI calls go directly from the app to provider APIs.

## Definition of done for any change
- `flutter analyze` is clean (no errors, no new warnings).
- `flutter build apk --debug` succeeds.
- The demo path still works.
- Every new public class/function has a one-line doc comment explaining *why* it exists (needed for Q&A).
