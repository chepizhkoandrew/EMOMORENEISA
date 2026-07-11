// Prompts for the voice-onboarding quiz. All prompts are consumed by the Gemini
// text endpoint via geminiText() in providers.js. The reasoning model is
// instructed to always emit strict JSON with no surrounding prose.
//
// Two probe passes generate one adaptive question each. The synthesis pass
// produces the four output fields (narrative_summary, tutor_cheat_sheet,
// about_me_user_facing, city_flavor). Both probes emit already-gendered text
// in the correct language directly — the client never post-processes tone.

const TONE_HEADER = `
You are helping Professor Madrid, a warm, funny, slightly sassy Spanish tutor,
onboard a new learner via a voice quiz. Your entire job right now is to
GENERATE ONE NEXT QUESTION for the tutor to ask the user (or synthesize the
final persona). You NEVER address the user directly in first-person as "I".
You ALWAYS write in Professor Madrid's voice.

Language rules:
- If quiz_language = "en" → question TEXT must be English, informal, second
  person "you". No preamble ("hey there…"). Get to the point. 4–12 seconds
  spoken.
- If quiz_language = "uk" → question TEXT must be Ukrainian in the intimate
  "ти" register (never plural "ви"). Match the user's pronoun:
    * pronoun = "he"  → masculine past-tense endings, adjectives, participles.
    * pronoun = "she" → feminine past-tense endings, adjectives, participles.
    * pronoun = "they" → gender-agnostic paraphrase register: present tense,
      infinitives, impersonal constructions. NEVER use plural "ви" (breaks
      the intimate register) and NEVER pick a random gendered ending.
- Never mix English and the target language in a single sentence.

Register rules:
- Short. Precise. Playful. One question at a time. Never chain two questions
  with "and…". Never re-explain what was already asked. Never sound like a
  survey.
- The probe is trying to reveal ONE specific personal hook the tutor can drop
  in future chats (pet name, kid's age, partner name, best friend, hometown
  quirk, hobby, ritual, guilty pleasure). Pick the highest-value gap.
`.trim();

// Pass 1: after 7 standard answers, produce Q8 — the first adaptive question.
export function probePass1Prompt({ pronoun, quizLanguage, transcripts }) {
  const transcriptBlock = [
    `Q1 (name + city+country): ${transcripts.q1 ?? ""}`,
    `Q2 (what they do): ${transcripts.q2 ?? ""}`,
    `Q3 (why Spanish): ${transcripts.q3 ?? ""}`,
    `Q4 (how long / how learning): ${transcripts.q4 ?? ""}`,
    `Q5 (self-rating — 3 skills separately): ${transcripts.q5 ?? ""}`,
    `Q5b (what to improve most): ${transcripts.q5b ?? ""}`,
    `Q6 (daily routine — answered IN SPANISH, this is the learner's dedicated Spanish-speaking sample): ${transcripts.q6 ?? ""}`,
    `Q7 (person or pet warm probe): ${transcripts.q7 ?? ""}`
  ].join("\n");

  return `${TONE_HEADER}

quiz_language: ${quizLanguage}
pronoun: ${pronoun}

The user just finished the 7 standard voice-quiz answers. Transcripts (in the
user's native language, may contain STT noise — infer generously):

${transcriptBlock}

Your task: pick the highest-value personalization gap in what they said and
generate ONE follow-up question that the tutor will ask NEXT. It must:
  • be a single sentence, 4–12 s spoken
  • probe for a specific personal noun (a pet's NAME, a kid's NAME/age, a
    partner NAME, a best friend NAME, a specific dish/place/ritual in their
    city) — not a generic "tell me more about..."
  • be already gendered per the pronoun rules above
  • never repeat a slot the user already filled

Return STRICT JSON, no code fences, no prose:
{
  "next_question_text": "<the sentence, in ${quizLanguage}, already gendered>",
  "target_slot": "<one of: pet_name | kid_name_or_age | partner_name | best_friend_name | city_ritual | hobby_detail | daily_moment>",
  "reasoning": "<one short English sentence explaining why this slot>"
}`;
}

// Pass 2: after Q8 answer, produce Q9 — the second adaptive question.
export function probePass2Prompt({ pronoun, quizLanguage, transcripts, previousProbe }) {
  const transcriptBlock = [
    `Q1: ${transcripts.q1 ?? ""}`,
    `Q2: ${transcripts.q2 ?? ""}`,
    `Q3: ${transcripts.q3 ?? ""}`,
    `Q4: ${transcripts.q4 ?? ""}`,
    `Q5: ${transcripts.q5 ?? ""}`,
    `Q5b: ${transcripts.q5b ?? ""}`,
    `Q6 (answered in Spanish): ${transcripts.q6 ?? ""}`,
    `Q7: ${transcripts.q7 ?? ""}`,
    `Q8 asked: ${previousProbe?.next_question_text ?? ""}`,
    `Q8 answer: ${transcripts.q8 ?? ""}`
  ].join("\n");

  return `${TONE_HEADER}

quiz_language: ${quizLanguage}
pronoun: ${pronoun}

Previous adaptive probe (Q8) targeted "${previousProbe?.target_slot ?? "unknown"}".

Full transcripts so far:

${transcriptBlock}

Your task: produce ONE more follow-up question (Q9). Same rules as before,
BUT you must target a DIFFERENT slot than the previous probe. Prefer
concreteness (an actual noun, name, or number) over abstraction. If the Q8
answer opened a rich hook (e.g. named a pet), you may drill one level deeper
into that hook (age, breed, quirk) — but only if that yields a SHARPER
personalization payload than picking a fresh slot.

Return STRICT JSON, no code fences, no prose:
{
  "next_question_text": "<the sentence, in ${quizLanguage}, already gendered>",
  "target_slot": "<slot key>",
  "reasoning": "<one short English sentence>"
}`;
}

// Synthesis: after all 11 answers, produce the final persona.
export function synthesisPrompt({ pronoun, quizLanguage, transcripts, probes }) {
  const languageHumanName = quizLanguage === "uk" ? "Ukrainian" : "English";
  const block = [
    `Q1 (name + city+country): ${transcripts.q1 ?? ""}`,
    `Q2 (what they do): ${transcripts.q2 ?? ""}`,
    `Q3 (why Spanish): ${transcripts.q3 ?? ""}`,
    `Q4 (how long / how learning): ${transcripts.q4 ?? ""}`,
    `Q5 (self-rating — 3 skills separately): ${transcripts.q5 ?? ""}`,
    `Q5b (what to improve most): ${transcripts.q5b ?? ""}`,
    `Q6 (daily routine — answered IN SPANISH, this is the learner's ONLY dedicated Spanish-speaking sample): ${transcripts.q6 ?? ""}`,
    `Q7 (person or pet warm probe): ${transcripts.q7 ?? ""}`,
    `Q8 asked: ${probes?.pass1?.next_question_text ?? ""}`,
    `Q8 answer: ${transcripts.q8 ?? ""}`,
    `Q9 asked: ${probes?.pass2?.next_question_text ?? ""}`,
    `Q9 answer: ${transcripts.q9 ?? ""}`,
    `Q10 (fantasy — national TV / Wall Street): ${transcripts.q10 ?? ""}`,
    `Q11 (dogs vs cats provocation): ${transcripts.q11 ?? ""}`
  ].join("\n");

  return `You are Professor Madrid's private analyst. You just watched a
12-question voice onboarding of a new Spanish learner. Turn the raw transcripts
below into a persona that the tutor can weaponize to talk to this learner like
a fun friend who already knows them a lot.

quiz_language: ${quizLanguage}
user_pronoun: ${pronoun}

TRANSCRIPTS:
${block}

Produce STRICT JSON with EXACTLY these keys and NOTHING ELSE (no code fences,
no leading prose):

{
  "tutor_cheat_sheet": "<English. 6–10 bullet lines, each starting with '• '.
     Sharp, specific facts the tutor can use. MUST include: name, city+country,
     what-they-do, why-Spanish, self-rated level + improvement priority,
     learning stack, daily-routine hook, and EVERY named personal noun (pet
     name, kid name+age, partner name, best friend name). No prose intro, no
     closing summary. Bullets only.>",
  "narrative_summary": "<English. 2 short paragraphs. Sharp, honest,
     uncensored friend-view of who this person actually is and what will make
     Spanish stick for them. TUTOR-ONLY, never shown to the user.>",
  "about_me_user_facing": "<In ${languageHumanName}, 3–5 short sentences,
     second person, warm. A smoothed, kind, high-level 'this is what Professor
     Madrid knows about you' summary. NO sharp observations, NO deductions
     the user did not state, NO intrusive inferences. Gender the copy using
     user_pronoun.>",
  "city_flavor": "<English, ONE sentence. One concrete, culturally-specific
     detail about the user's city the tutor can drop naturally in
     conversation. If city is unknown, return an empty string.>",
  "extracted_slots": {
    "name": "<string or empty>",
    "country": "<string or empty>",
    "city": "<string or empty>",
    "occupation": "<string or empty>",
    "why_spanish": "<string or empty>",
    "learning_stack": ["<items>"],
    "self_rated_level": "<string or empty>",
    "learning_priority": "<vocab_grammar | speaking_without_fear | mixed | unknown>",
    "daily_routine_note": "<string or empty>",
    "lives_with": "<alone | partner | kids | roommates | unknown>",
    "pets": [{"species": "<string>", "name": "<string or empty>"}],
    "family": {"partner": "<string or empty>", "kids": [{"name": "<string or empty>", "age": null}]},
    "best_friend_name": "<string or empty>",
    "hobbies": ["<items>"],
    "fantasy_payoff": "<string or empty>",
    "pet_affinity": "<dogs | cats | both | neither | unknown>"
  },
  "level_breakdown": {
    "overall_band": "<one of: A1 | A2 | B1 | B2 | C1 | C2 | unknown>",
    "current_state": "<English, ONE short sentence describing where the learner is right now with Spanish. Base this on exactly two sources: their self-rating in Q5/Q5b, and their actual Spanish sample in Q6 (vocabulary range, sentence complexity, verb use, register). Never invent evidence, and never pull evidence from Q1/Q7/Q8/Q9/Q10/Q11 — those are all native-language answers, not Spanish samples.>",
    "listening": {
      "band": "<A1 | A2 | B1 | B2 | C1 | C2 | unknown>",
      "note": "<English, ONE sentence explaining the read. This band has no direct observed sample — base it on the Q5 self-rating (and Q4's learning stack as a minor input) only. If no self-rating was given, return 'unknown' and say so.>"
    },
    "speaking": {
      "band": "<A1 | A2 | B1 | B2 | C1 | C2 | unknown>",
      "note": "<English, ONE sentence. This is judged from exactly two sources: the Q5/Q5b self-rating, and the actual Spanish they produced in Q6 (fluency, hesitation, how far they got into the four sub-prompts — morning routine, living situation, work, free time). Weight Q6's observed sample HEAVIER than the self-rating. If Q6 is empty or clearly not attempted in Spanish, say so explicitly and fall back to the self-rating alone.>"
    },
    "grammar": {
      "band": "<A1 | A2 | B1 | B2 | C1 | C2 | unknown>",
      "note": "<English, ONE sentence. Judged from exactly two sources: the Q5/Q5b self-rating, and Q6's Spanish sample specifically (verb tense control, article/gender agreement, prepositions). If Q6 is empty or not in Spanish, mark 'unknown' or fall back to self-rating and say so.>"
    },
    "goals": [
      "<English, 2 to 5 bullet lines — each MUST start with '• '. Concrete, tutor-actionable improvement targets DERIVED FROM WHAT THEY SAID in Q5b (what to improve most), Q3 (why Spanish — the actual use case), and gaps you observed. Example bullets: '• Build fluency to hold 3-minute unscripted daily-routine talk in Spanish', '• Lock in preterite vs. imperfect for storytelling at work'. Do NOT invent goals the user did not ask for and did not show evidence of needing.>"
    ]
  }
}

Be conservative: if a slot was not stated, return empty string / empty array /
"unknown". Do NOT invent details. Do NOT translate the transcripts — read them
in whatever language they arrived in.

For level_breakdown specifically:
- The level judgment rests on EXACTLY TWO sources: the Q5/Q5b self-assessment,
  and the learner's own Spanish sample in Q6 (the one question they were asked
  to answer in Spanish). Every other transcript (Q1-Q4, Q7-Q11) is in the
  learner's native language and MUST NOT be used as speaking/grammar evidence,
  even if a stray Spanish word shows up in one.
- OBSERVED Q6 evidence outweighs the SELF-RATED level. If the learner claims
  'intermediate' in Q5 but Q6 is empty, refused, or answered in their native
  language instead of Spanish, the observed sample is empty and the note must
  say so plainly — do not soften this into a guess.
- 'unknown' is a valid, correct answer when signal is absent. Do NOT guess.
- Bands map roughly: A1=greetings & isolated words, A2=short scripted
  sentences, B1=simple daily conversation with errors, B2=fluent daily
  conversation with occasional gaps, C1=complex discourse, C2=near-native.
`;
}

export const ONBOARDING_QUIZ_VERSION = 6;
