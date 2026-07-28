import Foundation

/// "Ask in a Free Forum" — the entry screen (NewSessionView's freeFormInput
/// step). The mode's actual replies (homework answers, corrections,
/// explanations) are model output in the interface language, produced by
/// PromptBuilder's freeForm* prompts — not static strings, so nothing to add
/// here for those.
let ukFreeFormStrings: [String: String] = [
    // SessionMode.displayLabel — filter chip + session-list fallback title
    "Free Forum": "Вільна форма",

    "What do you need? Paste homework, check something you wrote, or ask a question.":
        "Що тобі потрібно? Встав домашнє завдання, перевір щось написане або постав запитання.",
    "e.g. paste an exercise, \"is this right: ...\", or \"when do I use ser vs estar?\"…":
        "напр. встав вправу, «чи правильно: ...», або «коли вживати ser vs estar?»…",
    "Start": "Почати",
]
