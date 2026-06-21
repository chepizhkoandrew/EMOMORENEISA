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

## Implementation

Split `NewSessionView` into a two-step flow. Step 1 shows two illustrated mode cards. Step 2 (topic mode only) shows the text input + predefined topic chips. Street view directly creates a `.visual` session.

### [x] Step 1: Add illustrations to Assets.xcassets
- Extracted `topic_conversation` and `street_view` image sets (1x/2x/3x) from the provided zip into `Assets.xcassets`
- Created `Contents.json` for each imageset

### [x] Step 2: Rewrite NewSessionView.swift with two-step flow
- Step 1 screen: two large illustrated cards — "Learn a specific topic" (yellow gradient) and "Street view" (blue gradient)
- Step 2 screen: topic text input + mic button + predefined topic chips (FlowLayout)
- Toolbar: "Cancel" on step 1, custom "← Back" on step 2
- "Street view" tapping directly calls `createSession(mode: .visual)` — no topic step needed
- Removed the old `ModeCard` struct (was only used internally)

### [x] Step 3: UI iteration — card sizing and dock visibility
- Multiple rounds of card size, illustration placement, and text alignment refinement
- Final layout: illustrations pinned to right edge of card, text left-aligned and vertically centered
- Card height derived from illustration height (illustrationH * 0.21 capped at 170pt, cardH = illustrationH + 32)
- ScrollView wrapper + Spacer(minLength: safeAreaInsets.bottom + 24) ensures dock/home indicator is always visible
- Updated PromptBuilder.visualSystemPrompt for child-like street narration style
