import Foundation

// Ukrainian translations for "Learn by the Book" (Вчись по підручнику).
//
// Level-name keys ("Beginner", "Elementary", "Intermediate", "Upper
// Intermediate", "Advanced") deliberately AREN'T redefined here — they
// already exist in ukChatStrings/ukProfileStrings/ukLevelSettingsStrings,
// and `ukStrings` is one flat dictionary keyed by the English string, so
// reusing the same literal picks up the app's existing translation for free.
// Redefining them here would just be a coin-flip on merge order for which
// wording wins everywhere else that key is used. Only "Proficient" is new —
// this curriculum's top tier has no existing counterpart.
let ukLearnByBookStrings: [String: String] = [
    "Learn by the Book": "Вчись по підручнику",
    "structured lessons, topic by topic": "структуровані уроки, тема за темою",
    "Core words & phrases": "Основні слова й фрази",
    "Grammar focus": "Граматика теми",
    "Proficient": "Досконалий",

    // Quiz — voice-answer question page. "Question %d of %d", "Correct!",
    // "Not quite — \"%@\" is what we were going for.", "Finish", "Next",
    // "Transcribing…", "Listening… tap to stop" are reused verbatim from
    // ukSayItBetterStrings/ukMusicStrings/ukCommonStrings, not redefined here.
    "Tap to answer": "Торкнись, щоб відповісти",
    "Checking…": "Перевіряю…",
    "You said: \"%@\"": "Ти сказав(-ла): «%@»",
    "Try again": "Спробувати ще раз",

    // Quiz result screen
    "Perfect!": "Ідеально!",
    "Quiz complete!": "Тест завершено!",
    "%d of %d correct": "%d із %d правильно",
    "Retake quiz": "Пройти тест ще раз",
    "Review lesson again": "Повторити урок ще раз",
    "Next topic": "Наступна тема",
    "Back to topics": "До списку тем",

    // Topic detail CTA + status pill ("In progress"/"Completed" reused
    // verbatim from ukSayItBetterStrings)
    "Start quiz": "Почати тест",
    "Resume quiz": "Продовжити тест"
]
