# Chat Tutor Test Scenarios

## Goal
Run comprehensive backend simulation tests for the chat tutor system without touching the audio/TTS flow. Verify that: (1) profile digest is correctly injected into the system prompt, (2) the tutor behaves as expected in teaching style, (3) the analyst extraction correctly captures dynamic context (words, phrases, errors, goals, life facts), and (4) the @@GOAL: tag detection works.

## Affected Files
- `tests/chat_tutor_test.py` — standalone Python test runner (new)
- Mirrors logic from: `PromptBuilder.swift`, `ProfileAnalystService.swift`, `ChatOpenAIService.swift`

### [x] Step 1: Create test runner
- Write `tests/chat_tutor_test.py` that mirrors PromptBuilder and Analyst logic in Python
- 7 test scenarios covering: digest injection, cold start, rich context, goal detection, error extraction, life fact capture, exercise type identification
- No TTS/audio calls whatsoever
- Output: colored terminal report with pass/fail + raw LLM responses for inspection

### [x] Step 2: Run tests and capture output
- Execute `python3 tests/chat_tutor_test.py`
- Capture and review all scenario outputs

### [x] Step 3: Analyze and document findings
- Identify gaps or improvements in the system prompt script
- Document findings in `tests/results.md`

### [x] Step 4: Apply P0/P1 fixes and run enhanced v2 test suite
- Fixed @@GOAL: placement (moved to top of prompt with examples)
- Added dynamic max_tokens by student level (Beginner=300, Intermediate=512, Advanced=650)
- Added exercise variety rotation instruction when exercise_history is non-empty
- Wrote `tests/chat_tutor_test_v2.py` with 8 creative scenarios + token tracking
- Ran v2: 5/8 passed; added 1-hour lesson cost model ($0.106/hr, gpt-4o-mini)

### [x] Step 5: Upgrade to gpt-4.1, apply history window, run v3 tests
- Switched tutor model to `gpt-4.1` in `ChatOpenAIService.swift`
- Applied `suffix(20)` history window in `ChatView.swift`
- Added CEFR difficulty anchors to extraction prompt (fixed S4 difficulty calibration)
- Wrote `tests/chat_tutor_test_v3.py` with 9 scenarios including S9 (window validation)
- Ran v3: 5/9 passed; cost model confirmed at $0.641/hr (text only)
- Key remaining gap: @@GOAL: tag is architecturally broken — needs `GoalClassifierService`

### [x] Step 6: Tone, adaptive length, praise ban, numbered list design — v4/v5 runs
- Ran v4 (8 scenarios, tone/length focus): 5/8 passed
  - Identified: model used "Muy bien." / "Correcto:" as soft praise starters; numbered lists persisted at advanced level
- Applied adaptive signal-based length (replaces static level buckets in `PromptBuilder.swift`)
- Moved praise prohibition to `PROHIBICIÓN DE ELOGIO — REGLA ABSOLUTA` named block — full compliance achieved
- Applied Option A: numbered exercises allowed for 3+ parallel items; bullets/markdown still banned
- Wrote `tests/chat_tutor_test_v5.py` with 8 scenarios: adaptive length × 4, soft praise, numbered exercise, frustration, mixed-turn
- Ran v5: **8/8 passed** — first perfect score across all test runs
- Key remaining P0: `GoalClassifierService` (@@GOAL: architectural gap, not tackled in this session)
