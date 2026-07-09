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

### [x] Step 1: Shift text down in OnboardConsistencySlide
- Increased `.padding(.top, 60)` to `.padding(.top, 110)` in `OnboardingCarouselView.swift` for `OnboardConsistencySlide`. The image (phone thumbnail) is in a separate ZStack layer and remains unaffected.

### [x] Step 2: Make illustration twice bigger in SRSPlayerView
- Changed `LoroIllustrationView` `size: 160` to `size: 320` in `SRSPlayerView.swift`.

### [x] Step 3: Replace клюв/beak icon with standard play button
- Replaced `Image("icon_beak")` with `Image(systemName: "play.fill")` in `MessageBubbleView.swift` for the idle (not-yet-played) state of the speaker button.

### [x] Step 4: Double-tap message to open brain screen
- Added `.onTapGesture(count: 2)` to the bubble content in `MessageBubbleView.swift` that calls `onParrot()` for assistant messages, opening `ParrotWordGridView`.
