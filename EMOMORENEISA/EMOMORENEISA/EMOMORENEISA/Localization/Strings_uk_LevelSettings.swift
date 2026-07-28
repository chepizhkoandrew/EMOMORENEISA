import Foundation

/// Ukrainian translations for the new "Level" settings tab (graduated
/// 6-stage ladder, immersion mode, level-up toggles), ProfileView's level
/// summary link, and the Home level-up banner.
/// "Level", "Beginner", "Intermediate", "Advanced", "Learning Level" already
/// live in `ukProfileStrings` — reused here, not redefined.
let ukLevelSettingsStrings: [String: String] = [
    "Stage, immersion & CEFR skills": "Етап, занурення й навички CEFR",
    "Manage level": "Керувати рівнем",
    "CEFR overall: %@": "CEFR загалом: %@",

    // New stage names (Beginner/Intermediate/Advanced already in ukProfileStrings)
    "Absolute Beginner": "Абсолютний початківець",
    "Elementary": "Елементарний",
    "Upper Intermediate": "Вище середнього",

    // Stage tutoring descriptions (LevelSettingsView + ProfileView summary)
    "Your tutor speaks almost entirely in your native language, introducing a few simple Spanish words at a time.":
        "Твій репетитор говорить майже повністю рідною мовою, поступово вводячи кілька простих іспанських слів.",
    "Your tutor mixes short, simple Spanish sentences with plenty of native-language support.":
        "Твій репетитор поєднує короткі прості іспанські речення з великою підтримкою рідною мовою.",
    "Your tutor leans more into Spanish, still explaining new grammar in your native language.":
        "Твій репетитор більше переходить на іспанську, але й далі пояснює нову граматику рідною мовою.",
    "Your tutor speaks mostly in Spanish, switching to your native language mainly for grammar notes.":
        "Твій репетитор говорить переважно іспанською, переходячи на рідну мову здебільшого для граматичних приміток.",
    "Your tutor speaks almost entirely in Spanish, with rare native-language asides.":
        "Твій репетитор говорить майже повністю іспанською, лише зрідка вставляючи рідну мову.",
    "Your tutor speaks like a native speaker — full Spanish, no simplification.":
        "Твій репетитор говорить як носій мови — повністю іспанською, без спрощень.",

    // Your level section
    "Your level": "Твій рівень",
    "Tap a stage to jump straight to it.": "Торкнись етапу, щоб одразу перейти до нього.",

    // Skill breakdown section
    "Skill breakdown": "Розбір навичок",
    "Listening": "Аудіювання",
    "Speaking": "Говоріння",
    "Grammar": "Граматика",
    "This CEFR read comes from your voice onboarding and may not always match the stage above — they're independently adjustable.":
        "Ця оцінка CEFR базується на голосовому опитуванні й може не завжди збігатися з етапом вище — вони налаштовуються незалежно.",
    "Complete the voice onboarding to unlock a per-skill CEFR read.":
        "Пройди голосове опитування, щоб отримати оцінку CEFR за кожною навичкою.",

    // Immersion mode section
    "Immersion mode": "Режим занурення",
    "Spanish immersion": "Занурення в іспанську",
    "Gentle": "М'який",
    "Guided": "Керований",
    "Immersive": "Занурення",
    "More native language, ease in slowly": "Більше рідної мови, поступове занурення",
    "Balanced for your level": "Збалансовано для твого рівня",
    "Push toward more Spanish": "Більше іспанської",
    "Nudges how much Spanish vs. %@ your tutor uses, without changing your measured level.":
        "Це впливає на співвідношення іспанської та %@ у відповідях репетитора, не змінюючи твій виміряний рівень.",

    // Preferences toggles
    "Preferences": "Налаштування",
    "Absolute beginner mode": "Режим абсолютного початківця",
    "Always speak to me almost entirely in %@, regardless of my measured level.":
        "Завжди говорити зі мною майже повністю %@, незалежно від мого виміряного рівня.",
    "Show translations inline": "Показувати переклад одразу",
    "Show the %@ meaning next to new Spanish words and phrases.":
        "Показувати значення %@ поруч із новими іспанськими словами й фразами.",
    "Suggest when I'm ready to level up": "Підказувати, коли я готовий(-а) перейти на новий рівень",
    "Show a banner on Home when you're consistently doing well at your current level.":
        "Показувати банер на Головній, коли ти стабільно добре справляєшся на поточному рівні.",

    // Home level-up banner
    "Ready to level up to %@?": "Готовий(-а) перейти на рівень «%@»?",
    "Level up": "Підвищити рівень",
]
