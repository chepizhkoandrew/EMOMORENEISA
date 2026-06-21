# Multi-model Pipeline
---

## Instructions

This workflow runs a 4-phase pipeline with two human-in-the-loop confirmation gates:

1. **Planning phase** — one `zenflow-planner` subagent creates the implementation plan directly.
2. **Gate A: User confirmation of plan** — you STOP and ask the user to approve the plan before implementation runs.
3. **Implementation** — one `zenflow-implementer` applies the plan. Single pass, no loop between subagents.
4. **Review Decision Gate** — assess whether review is needed based on change scope and user intent. Small/easy changes skip review by default. The user can explicitly opt in or out. When uncertain, ask the user.
5. **Review (conditional)** — only if the Review Decision Gate decides to run it: one `zenflow-review-orchestrator` subagent writes a consolidated review.
6. **Gate B: User confirmation of review** — only if review ran. You STOP and ask the user to approve the review findings before the fix pass runs.
7. **Single-pass fix (conditional)** — only if the consolidated review verdict is `REQUEST CHANGES` (and the user approved in Gate B), one `zenflow-fixer` addresses the P0/P1/P2 findings. No re-review unless user asks for it.

You are the top-level orchestrator. Each subagent phase (steps 1, 3, 5, and 7 above) is ONE subagent call. Once a subagent finishes its turn cleanly, NEVER resume it. Resume is ONLY allowed for recovery (the subagent errored out, asked a clarifying question, or refused to proceed), except where explicitly allowed in Gate A and Gate B.
You must complete all 4 subagent phases sequentially, pausing for explicit user confirmation at Gate A (after Phase 1) and Gate B (after Phase 3).
When passing file paths to subagents, use FULL absolute paths inside `{@artifacts_path}`. Do NOT use `~` or `$HOME` — subagents will not expand them.

When calling `spawn_subagent`, on the initial spawn you MUST pass all files the subagent needs at startup (plans, reports, reviews) via the `attachedFiles` parameter (an array of absolute paths). Do NOT embed file contents in the prompt — the subagent will read attached files automatically. Reference the files by path in the prompt so the subagent knows what each one is for.
On resume, if the subagent needs to read any file that is new since the initial spawn, or any file whose content has changed, pass those file paths via `attachedFiles` on the resume call as well. Reference each attached file by path in the resume prompt and instruct the subagent to re-read it. Files already attached at spawn that have not changed do not need to be re-attached.

The required skills are pre-installed; you have rights to use them.

**Model defaults**: The model IDs listed in this workflow are *suggested defaults*. If the user asks for specific models, honor that override. If a listed model is unavailable, substitute the most-capable available alternative for the same role or perspective and continue — do not fail.

**Artifact paths** (resolve `{@artifacts_path}` to its absolute form before passing to subagents):

- Final plan: `{@artifacts_path}/final_plan.md`
- Implementation report: `{@artifacts_path}/implementation_report.md`
- Consolidated review: `{@artifacts_path}/final_review.md`
- Fix report (only if Phase 4 runs): `{@artifacts_path}/fix_report.md`

---

## Phase 1: Planner — produces `{@artifacts_path}/final_plan.md`

Spawn ONE planner subagent (NO resume — fresh).

Call `spawn_subagent`:

- model: `opus-4-7-think`
- skill: `zenflow-planner`
- prompt:
  > The user task is <task-description>.
  >
  > Write the final implementation plan to `{@artifacts_path}/final_plan.md`.

The planner could end its turn for two reasons: it wants to ask the user a question, or it has successfully finished planning.
If it wants to ask a question, ask the user using the mcp__zenflow__ask_user tool or plain text. After you get an answer, resume the subagent with this answer.
If it finished planning successfully, check that the file exists and is non-empty. If not, resume the subagent and ask it to continue planning and write the plan to the required location.

---

## Gate A: User confirmation of plan — MANDATORY, STOP HERE

**Do NOT proceed to Phase 2 until the user has approved the plan.** This is a hard gate.

1. Read `{@artifacts_path}/final_plan.md` that the planner wrote.

2. Prefer calling the `ask_artifact_review` MCP tool with:
   - `file_path`: absolute path to `{@artifacts_path}/final_plan.md`

   This tool renders the artifact in a rich UI where the user can read the full file, add comments, and choose an action. The tool **blocks** until the user responds.

   If the user declines the tool, or if the tool is unavailable/fails, fall back to plain text: ask the user to review `{@artifacts_path}/final_plan.md` directly and reply with either `Proceed`, `Continue with comments`, `Address changes`, or `Cancel`, plus any optional comments. If they reply in free text instead of using those exact labels, infer the closest action from their message.

3. Interpret the review result from either path:
   - **Tool path**: `answers[0].selected` contains the action and `answers[1].custom_answer` contains free-text feedback (may be empty).
   - **Plain-text fallback**: treat the user's message as the action source and preserve the rest of their message as feedback when relevant.
   - Action handling:
     - `"Proceed"` → proceed immediately to Phase 2 below.
     - `"Continue with comments"` → proceed to Phase 2 and pass the user's comments to the implementer for awareness (no rework needed).
     - `"Address changes"` → the user wants modifications. Capture their feedback.
     - `"Cancel"` → do NOT run Phases 2–4. Post `Pipeline aborted after Phase 1 by user request.` and stop.

4. If the user selected `"Address changes"`:
   - If Gate A used `ask_artifact_review` and returned `results_file`, store that path and **resume** the planner subagent (use its session-id from Phase 1) with:
     - attachedFiles: `[ "{@artifacts_path}/final_plan.md", "<results_file>" ]`
     - prompt:
       > The user reviewed the plan at `{@artifacts_path}/final_plan.md` and requested changes.
       >
       > Structured review results file: `<results_file>` (attached). Re-read it for the full answer array before updating the plan.
       >
       > USER FEEDBACK: <paste the user's feedback verbatim>
       >
       > Read the current plan, apply the user's feedback, and write the updated plan back to `{@artifacts_path}/final_plan.md`.
   - If only plain-text feedback is available, resume the planner subagent with:
     - attachedFiles: `[ "{@artifacts_path}/final_plan.md" ]`
     - prompt:
       > The user reviewed the plan at `{@artifacts_path}/final_plan.md` and requested changes.
       >
       > USER FEEDBACK: <paste the user's feedback verbatim>
       >
       > Read the current plan, apply the user's feedback, and write the updated plan back to `{@artifacts_path}/final_plan.md`.
   - After the planner finishes, go back to step 1, re-read the updated plan, and re-enter this gate. Prefer `ask_artifact_review` again, but keep supporting the same plain-text fallback until the user approves or aborts.
---

## Phase 2: Implementation
Call `spawn_subagent`
- model: `gpt-5.3-codex`
- skill: `zenflow-implementer`
- attachedFiles: `[ "{@artifacts_path}/final_plan.md" ]`
- prompt:
  > Plan: `{@artifacts_path}/final_plan.md` (attached)
  > Write your implementation report to `{@artifacts_path}/implementation_report.md`.
  > Before calling `spawn_subagent`, resolve the `<if …> … </if …>` block below yourself: if the user selected `Continue with comments` at Gate A and provided non-empty feedback, replace the `<if …>` block with a single line `User comments on the approved plan: <paste comments verbatim>`. Otherwise delete the `<if …>` block entirely. The literal angle-bracket tags must not reach the subagent.
  > <if user selected `Continue with comments` and provided feedback> User comments on the approved plan: <user-comments> </if user selected `Continue with comments` and provided feedback>
  > The user task is: <task-description>.

After implementation is complete, proceed to the next gate.

---

## Review Decision Gate: Decide whether to run review — EVALUATE HERE

After implementation completes, you MUST decide whether to run the review phase (Phase 3). The review uses 3 parallel workers across 3 models — it is expensive. For small/easy changes, skipping it saves significant cost.

**Decision logic (evaluate in this order):**

1. **User explicitly opted out of review** — If the user's original task description contains phrases like "no review", "skip review", "don't review", "without review", or similar → **SKIP review entirely**. Do NOT write any review artifacts. Skip Phase 3, Gate B, and Phase 4 completely. Notify the user: "Skipping review as requested." Pipeline is done after implementation.

2. **User explicitly requested review** — If the user's original task description contains phrases like "review this", "run review", "with review", "do review", or similar → **RUN review** (proceed to Phase 3).

3. **Assess change scope** — Read the implementation report at `{@artifacts_path}/implementation_report.md` and run `git diff` to assess the actual changes. Consider:
   - Number of files changed
   - Total lines added/removed
   - Whether changes touch critical paths (auth, payments, data models, API contracts, security)
   - Whether it's a simple/mechanical change (typo fix, config tweak, dependency bump, copy change, single-line fix)

4. **Apply threshold:**
   - **Clearly small** (≤3 files changed, ≤50 lines diff, no critical paths, mechanical/simple change) → **SKIP review**. Do NOT write any review artifacts. Skip Phase 3, Gate B, and Phase 4. Notify the user: "Change is small — skipping review to save cost. Say 'review' if you'd like one." Pipeline is done.
   - **Clearly large** (>10 files, >200 lines, touches critical paths, complex logic changes) → **RUN review** (proceed to Phase 3).
   - **Uncertain / medium** → **ASK the user** in plain text (do NOT use MCP tools for this). Post a message like:
     > The implementation changed N files (~M lines). Would you like to run the review phase? (3 parallel reviewers — adds cost but catches issues.)
     >
     > Reply "yes" to review, or "no" to skip.

     Wait for the user's reply. If user says yes → proceed to Phase 3. If user says no → skip review, no artifacts needed. Pipeline is done.

---

## Phase 3: Review Orchestrator — produces `{@artifacts_path}/final_review.md`

Spawn the review orchestrator subagent.
The orchestrator will internally spawn 3 review workers in parallel (one per model below) and consolidate their findings into a single review.

Call `spawn_subagent`:

- model: `gpt-5-3-codex`
- skill: `zenflow-review-orchestrator`
- attachedFiles: `[ "{@artifacts_path}/final_plan.md", "{@artifacts_path}/implementation_report.md" ]`
- prompt:
  > Worker models:
  > - 1: opus-4-7-think
  > - 2: gpt-5.3-codex
  > - 3: gemini-3-1-pro-preview
  >
  > Worker output paths:
  > - Worker 1: `{@artifacts_path}/review_worker_1.json`
  > - Worker 2: `{@artifacts_path}/review_worker_2.json`
  > - Worker 3: `{@artifacts_path}/review_worker_3.json`
  >
  > Plan path: `{@artifacts_path}/final_plan.md` (attached)
  > Implementation report path: `{@artifacts_path}/implementation_report.md` (attached)
  > Consolidated output path: `{@artifacts_path}/final_review.md`
  >
  > The user task is <task-description>.
  > Spawn the 3 workers in parallel using the `zenflow-review-worker` skill, one per worker model above. Each worker writes its raw findings JSON to its assigned worker output path. After all 3 complete, dedupe and verify the findings (read the actual code to confirm each one) and write the consolidated review to the consolidated output path as a Markdown file. Include a JSON code block with the verdict and findings array so downstream phases can parse it.

Then wait for the subagent to finish. If it errored out, try resuming it once.

---

## Gate B: User confirmation of review — MANDATORY (only if review ran), STOP HERE

**If review was skipped** (Review Decision Gate decided to skip Phase 3), the pipeline is already done — skip Gate B and Phase 4 entirely.

**If review ran but found nothing** (the verdict in `final_review.md` is `"APPROVE"` and the `findings` array is empty) → do NOT call the review gate tool. Instead, notify the user in plain text: "Review completed — no issues found." Skip Gate B and proceed directly to Phase 4 (which will see APPROVE and exit cleanly). Pipeline is complete.

**If review ran and found issues:** Do NOT proceed to Phase 4 until the user has approved the review artifact. This is a hard gate.

1. Read `{@artifacts_path}/final_review.md`. If you need to fall back to plain text, explicitly tell the user that by default Phase 4 will only fix P0/P1/P2 issues unless they ask for a different scope.

2. Prefer calling the `ask_artifact_review` MCP tool with:
   - `file_path`: absolute path to `{@artifacts_path}/final_review.md`

   This tool renders the review artifact in a rich UI and lets the user choose an action. The tool **blocks** until the user responds.

   If the user declines the tool, or if the tool is unavailable/fails, fall back to plain text: ask the user to review `{@artifacts_path}/final_review.md`, remind them that the default fix scope is P0/P1/P2 only, and ask them to reply with either `Proceed`, `Continue with comments`, `Address changes`, or `Cancel`, plus any optional scope overrides or feedback. If they reply in free text instead of using those exact labels, infer the closest action from their message.

3. Interpret the review result from either path:
   - **Tool path**: `answers[0].selected` contains the action and `answers[1].custom_answer` contains free-text feedback (may be empty).
   - **Plain-text fallback**: treat the user's message as the action source and preserve the rest of their message as feedback when relevant.
   - Action handling:
     - `"Proceed"` → proceed to Phase 4 using the default scope (P0/P1/P2 only) unless the user provided a scope override.
     - `"Continue with comments"` → proceed to Phase 4 and pass the user's comments or scope overrides to the fixer.
     - `"Address changes"` → user asked to revise the review artifact first; capture their feedback.
     - `"Cancel"` → stop. Post `Pipeline aborted after review gate by user request.` Pipeline complete.

4. If the user selected `"Address changes"`:
   - If Gate B used `ask_artifact_review` and returned `results_file`, store that path and resume the Phase 3 review orchestrator subagent (use its session-id) with:
     - attachedFiles: `[ "{@artifacts_path}/final_review.md", "<results_file>" ]`
     - prompt:
       > The user reviewed the findings at `{@artifacts_path}/final_review.md` and requested changes.
       >
       > Structured review results file: `<results_file>` (attached). Re-read it for the full answer array before updating the review.
       >
       > USER FEEDBACK: <paste the user's feedback verbatim>
       >
       > Read the current `final_review.md`, apply the user's feedback, and write the updated review back to `{@artifacts_path}/final_review.md`.
   - If only plain-text feedback is available, resume the Phase 3 review orchestrator subagent with:
     - attachedFiles: `[ "{@artifacts_path}/final_review.md" ]`
     - prompt:
       > The user reviewed the findings at `{@artifacts_path}/final_review.md` and requested changes.
       >
       > USER FEEDBACK: <paste the user's feedback verbatim>
       >
       > Read the current `final_review.md`, apply the user's feedback, and write the updated review back to `{@artifacts_path}/final_review.md`.
   - After it finishes, return to step 1, re-read the updated review, and re-enter this gate. Prefer `ask_artifact_review` again, but keep supporting the same plain-text fallback until the user approves or aborts.

---

## Phase 4: Single-Pass Fix

If the Review Decision Gate skipped Phase 3, or Gate B was skipped because the review was APPROVE with no findings, skip Phase 4 and exit the pipeline. Do not attempt to read `final_review.md`.

1. Call `spawn_subagent` (NO resume — this is a FRESH fixer agent, NOT the Phase 2 implementer):
   - model: `gpt-5.3-codex`
   - skill: `zenflow-fixer`
   - attachedFiles: `[ "{@artifacts_path}/final_review.md", "{@artifacts_path}/final_plan.md", "{@artifacts_path}/implementation_report.md" ]`
   - prompt:
     > The user task is: <task-description>.
     > The implementation has issues confirmed by reviewers.
     > Read the consolidated review at `{@artifacts_path}/final_review.md` (attached).
     > Read the original plan at `{@artifacts_path}/final_plan.md` (attached) for context.
     > Read the implementation report at `{@artifacts_path}/implementation_report.md` (attached) to see what was already done.
     > <if user selected `Continue with comments` and provided feedback> User comments on the approved review: <user-comments> </if user selected `Continue with comments` and provided feedback>
     > Run tests to verify each fix.
     > Write your fix report to `{@artifacts_path}/fix_report.md`.
     > The user task is described above.

2. Once the fixer finishes its turn cleanly, do NOT resume it. Do NOT spawn a second review. This is the final pipeline step.
After that step, the user could ask to run the review again, run another planning round, or implement another change. Treat this as a follow-up and restart from the relevant part of the pipeline.