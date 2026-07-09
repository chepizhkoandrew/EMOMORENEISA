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

Two changes in `EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Views/Intro/OnboardingCarouselView.swift`:

### [x] Step 1: Rework OnboardDogSlide (screen 0)
- Removed speech bubble (`reversedBubble`, `ReverseTailShape`)
- Text displayed directly with H1 font (30pt, `.black`, `.rounded`) — same as other slides
- Updated line: "methods" → "techniques", "better remembering" → "BETTER REMEMBERING"
- `displayedAttributedText` highlights: "app for learning Spanish" and "dog training techniques" in yellow, "NLP" in yellow, "BETTER REMEMBERING" in bright orange-yellow at 34pt (extra emphasis)
- Typing effect and cursor blink unchanged

### [x] Step 3: Fix cursor-blink layout jumps — hardcoded line breaks
- Replaced character-string approach with `TypeSeg`-based row system
- Each sentence has exactly 3 hardcoded rows; no dynamic word-wrap occurs
- Ghost row (opacity 0) always reserves full final layout of current row
- Cursor is always `|` char — toggles color between `.yellow` and `.clear` (same width, zero layout shift)
- All state mutations in `@MainActor` async functions

### [x] Step 2: Rework slide 1 (street view)
- Replaced `OnboardFeatureSlide` tag 1 with new `OnboardStreetViewSlide`
- H1: "Street view - learn anywhere!"
- Numbered list: 1. Take a picture of what you see around / 2. Professor will give you words to describe it / 3. Talk with professor about it
- Footer text: "This is how children do - they remember what they see!" + "And they always have someone to talk about it."
