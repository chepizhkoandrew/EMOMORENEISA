# Three Tweaks Implementation

### [x] Step 1: Trial treats — 250 free
Changed `server/src/config.js` default `TRIAL_GRANT_TREATS` from 50 → 250 and updated the matching Supabase migration seed value. The Railway env var `TRIAL_GRANT_TREATS` should also be set to 250 to take effect on the live server.

### [x] Step 2: Verbs game — recording only, no conflict
- Removed the 0.3 s delay before recording in `GameEngine.startCellTimer()` (delay was a leftover from pronoun audio playback that no longer exists).
- Changed `AudioRecorder.start()` session category from `.record` to `.playAndRecord` with `.duckOthers` — this prevents the exclusive-record mode from clashing with the background music session, which was the root cause of silent recordings (peak ≤ 0.06) and all-verbs-failing.
- Added session restore (`.ambient` + deactivate) in both `stopAndTranscribe()` and `cancel()` so background music can resume cleanly after each cell.

### [x] Step 3: Visual/street mode — session goal in context + dynamic goal updates
- Updated `PromptBuilder.visualSystemPrompt()` to accept an optional `goal` parameter and inject a "Session focus" line into the system prompt.
- Updated `ChatView.generateAssistantReply()` to pass `session.sessionGoal ?? session.topic` to the visual prompt (was ignored before).
- Migrated `GoalClassifierService` from calling OpenAI directly with a bundle API key to using `ProxyClient.shared.utility()`. This fixes goal detection silently failing and removes the API key from the client binary.

---

## Original Instructions

Ask the user questions when anything is unclear or needs their input. This includes:
- Ambiguous or incomplete requirements
- Technical decisions that affect architecture or user experience
- Trade-offs that require business context

Do not make assumptions on important decisions — get clarification first.

**Debug requests, questions, and investigations:** answer or investigate first. Do not create a plan upfront — the user needs an answer, not a plan. A plan may become relevant later once the investigation reveals what needs to change.

**For all other tasks**, before writing any code, assess the scope of the actual change (not the prompt length — a one-sentence prompt can describe a large feature). Scale your approach:

- **Trivial** (typo, config tweak, single obvious change): implement directly, no plan needed.
- **Small** (a few files, clear what to do): write 2–3 sentences in `plan.md` describing what and why, then implement. No substeps.
- **Medium** (multiple components, design decisions, edge cases): write a plan in `plan.md` with requirements, affected files, key decisions, verification. Break into 3–5 steps.
- **Large** (new feature, cross-cutting, unclear scope): gather requirements and write a technical spec first (`requirements.md`, `spec.md` in `{@artifacts_path}/`). Then write `plan.md` with concrete steps referencing the spec.

**Skip planning and implement directly when** the task is trivial, or the user explicitly asks to "just do it" / gives a clear direct instruction.

To reflect the actual purpose of the first step, you can rename it to something more relevant (e.g., Planning, Investigation). Do NOT remove meta information like comments for any step.

Rule of thumb for step size: each step = a coherent unit of work (component, endpoint, test suite). Not too granular (single function), not too broad (entire feature). Unit tests are part of each step, not separate.

Update `{@artifacts_path}/plan.md` if it makes sense to have a plan and task has more than 1 big step.
