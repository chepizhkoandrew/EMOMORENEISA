# Auto

## Configuration
- **Artifacts Path**: {@artifacts_path} → `.zenflow/tasks/{task_id}`

## Agent Instructions

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

### [x] Step: Replace parrot emoji with seagull images throughout the app
- Removed all 🦜 emoji from ParrotPlayerView, ParrotWordGridView, LoopingParrotPlayer, MemoryCardNotificationService, LoroMemorizeHubView
- Generated seagull_chat_icon.png and wired it into MessageBubbleView parrot button
- Populated all loro_* imageset slots with appropriate seagull PNGs

### [x] Step: Increase seagull image sizes on all screens
- Hub view: 150 → 230
- SRS Player: 96 → 160 (now playing), 110 → 200 (session complete)
- Vocabulary view: 96 → 150 (empty state), 110 → 160 (card detail)
- ParrotPlayerView: 72 → 120 (both states)

### [x] Step: Rework CTA button and remove duplicate chat button
- Renamed "Loro Memorize!" → "Practice Memory"
- Hide Practice Memory button entirely when dueCards is empty
- Removed duplicate chat button from header toolbar
- Removed "Nothing due right now" heading and description text; show only "Teach Seagull Steven in Chat" button when nothing is due

### [x] Step: Fix build warnings
- Renamed professor_dog.PNG → professor_dog.png and updated Contents.json
- Added missing iPad 76x76 icon entry to AppIcon Contents.json
- Added emitLocalSessionAsInitialSession: true to SupabaseClient
