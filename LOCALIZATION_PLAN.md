# Ukrainian Localization — Full App Coverage Audit

The app localizes via the global `L(...)` function; UK strings live in per-area
partial dicts merged in `Localization/Strings_uk.swift`. A key missing from its
dict falls back to English. Spanish learning content and brand names stay as-is.

## Dictionary population state (entries)
| Dict (area)        | Entries | State |
|--------------------|---------|-------|
| ukCommonStrings    | 13      | shared (Continue/Cancel/Done/Save/Close/Back/Next/Skip/Retry/Loading…/Settings/Language/App Language) |
| ukIntroStrings     | 47      | DONE (Onboarding) |
| ukHomeStrings      | 6       | DONE (ModeSelectorView) |
| ukGameStrings      | 26      | DONE (Game/Slot/Results/Timer) |
| ukChatStrings      | 0       | **EMPTY — Chat/Sessions/Auth/Annotation NOT translated** |
| ukBillingStrings   | ~48     | DONE (this task) |
| ukParrotStrings    | ~24     | DONE (this task) |
| ukProfileStrings   | 0       | **EMPTY — Profile NOT translated** |
| ukMemorizeStrings  | 0       | **EMPTY — Memorize/SRS NOT translated** |

## Per-screen status
Legend: DONE / WRAPPED-NO-DICT (L() used but dict empty → shows English) /
NOT-WRAPPED (literals still raw) / OK (only data/Spanish left).

### Billing  — DONE
- PaywallView.swift — DONE
- BillingInfoView.swift — DONE

### Parrot — DONE
- ParrotPlayerView.swift — DONE (only Spanish "¡Bien hecho!" left, correct)
- ParrotWordGridView.swift — DONE

### Intro / Home / Game — already covered
- OnboardingCarouselView (38 L) — OK (only Spanish demo strings left)
- TypewriterIntroView (10 L) — OK
- Home/ModeSelectorView (6 L) — DONE
- GameMatrixView / SlotMachine / SpinningWheel / ResultsView — OK (only numeric/data)
- Views/Home/HomeView.swift — root shell, no translatable chrome (only numeric)

### CHAT area — NEEDS WORK (ukChatStrings empty)
- ChatView.swift — WRAPPED-NO-DICT. 15 keys need UK entries:
  "Beginner","Camera","Dismiss","Free conversation",
  "Listening… tap mic to stop","Photos","Record","Save","Sending…",
  "Session Focus","Speak your focus or type it. Professor Madrid will jump
  straight into teaching it from the very first message.","Stop","Transcribing…",
  "What are we focusing on in this session?",
  "e.g. past tense, ser vs estar, travel vocabulary…"
- MessageBubbleView.swift — WRAPPED-NO-DICT ("Reply in Thread") + 1 more raw
- ThreadSheetView.swift — NOT-WRAPPED: "Thread","Done","Original message",
  "Reply in thread…"
- NewSessionView.swift — NOT-WRAPPED (10): "What topic do you want to learn about?",
  "Transcribing…","Listening… tap mic to stop","Quick topics","Start Conversation",
  "Add up to 4 photos of what is around you.","Visual learning: remember words 5×
  faster from photos of your real life.","Camera","Photos","Start Conversation"
- SessionListView.swift — NOT-WRAPPED (5): "Chat Tutor","No sessions yet",
  "Start your first Spanish lesson\nwith Professor Madrid.","Start First Lesson"
  ( "\(wallet.balanceTreats)" = numeric, skip )
- SignInView.swift — NOT-WRAPPED: "Sign in to save your progress\nand continue
  your Spanish journey.","Continue with Google"
  ( "¡Hola!" Spanish, "PROFESSOR MADRID" brand → skip )
- AnnotationCanvasView.swift — NOT-WRAPPED (6): "Go to memory queue (%d)",
  "Tap mic to chat about what you see","Mapping the scene…",
  "Professor Madrid is pinpointing each object","Could not map the scene","Try Again"

### PROFILE area — NEEDS WORK (ukProfileStrings empty)
- ProfileView.swift — 4 wrapped (App Language/Done/Language/My Profile) need dict;
  + 15 NOT-WRAPPED: "Sign out?","Sign Out","Delete your account?","Delete Account
  Permanently","This will permanently delete your account, all sessions, memory
  cards, and treat balance. This cannot be undone.","%d treats"(→ balanceTreats),
  "Tap to top up","Get more","Automatic voice replies","Turn off to save treats —
  tap a message to hear it on demand.","Level"(Picker),"e.g. subjunctive mood,
  travel vocabulary","Sign Out","Delete My Account"
  ( "\(lang.flag)  \(lang.nativeName)" = data, skip )

### MEMORIZE area — NEEDS WORK (ukMemorizeStrings empty)
- LoroMemorizeHubView.swift — WRAPPED-NO-DICT. 13 keys: "%d day","%d hour","%d min",
  "Due later","Due now","Next practice in %@","No words yet","Practice Memory",
  "Teach Seagull Steven in Chat","Use Explore mode to discover and add words to
  your queue","in %d day","in %d hour","in %d min"
- LoroStatsView.swift — WRAPPED-NO-DICT (6: "%d plays","All","Known","Memory
  pipeline","Progress","This week") + "Search words" raw
- MemorizeSettingsView.swift — NOT-WRAPPED (15): "Session","Auto-advance words",
  "Reminders","Daily reminder","Reminder hour: %d:00","Vacation","Pause all
  scheduling","Reset all progress","Memorize Settings","Done","Reset all progress?",
  "Cancel","Reset","This permanently deletes every memory card. Seagull Steven
  will forget all his words. This cannot be undone.","%@: %d"(genericStepper)
- LoroVocabularyView.swift — NOT-WRAPPED (7): "Seagull Steven's Vocabulary",
  "Finish a parrot loop in Chat to teach Seagull Steven his first word.",
  "Search words","Replay (doesn't change Loro's schedule)","Remove Word?",
  "Remove","Cancel"
- MemorizeContainerView.swift — NOT-WRAPPED tab labels: "Seagull","Progress"
- SRSPlayerView.swift — NOT-WRAPPED (6): "Word %d of %d","Repetition %d of %d",
  "Next word","You refreshed N word(s) with Seagull Steven.","🧠 N word(s) etched
  in a microchip — Loro won't forget them for years!","Back to Seagull Steven"
- MicrochipCelebrationView.swift — MIXED ES/EN (needs restructure): "¡Eso es! Loro
  won't forget this for years. That's word #\(knownCount)." / "Seagull Steven knows
  N word(s)" / "¡Vamos!"(Spanish, skip)

## Translation-quality improvements to apply
1. PLURALS: many EN strings inline-pluralize ("word" + (n==1 ? "" : "s")). Ukrainian
   has 3 plural forms (1 слово / 2 слова / 5 слів). Simple "%@"/"%d" templates will
   read wrong. Add a small UK plural helper (e.g. plural(n, "слово","слова","слів"))
   or split keys per form. Affects SRSPlayerView, MicrochipCelebrationView,
   LoroMemorizeHubView time strings ("%d day/hour/min").
2. MASCOT NAMING CONSISTENCY: source mixes "Seagull Steven" and "Loro" for the same
   bird, plus "Professor Madrid". Decide UK canon (used so far: "Чайка Стівен";
   "Loro" kept as name). Keep consistent across Memorize + Chat.
3. MIXED ES/EN STRINGS: MicrochipCelebration "¡Eso es! ... word #N" bundles a
   Spanish exclamation with English UI in one literal — split so only the English
   part is localized and the Spanish stays.
4. DEDUPE COMMON KEYS: "Done"/"Close" already in ukCommonStrings; I also added them
   to ukBillingStrings (harmless override). Prefer reusing common keys; likewise
   reuse "Cancel","Language","App Language","Settings","Retry" in Chat/Profile/
   Memorize instead of re-adding.
5. INTERPOLATION SANITY: convert "\(x) treats" style to L("%@ treats", …) with
   %d for Int, %@ for String; never wrap StoreKit displayPrice, lang.nativeName,
   verb.rawValue, or pure numeric counters.

## Recommended implementation order (if approved)
1. CHAT (most user-facing): SessionListView, NewSessionView, ChatView dict,
   MessageBubbleView, ThreadSheetView, SignInView, AnnotationCanvasView → ukChatStrings
2. PROFILE: ProfileView → ukProfileStrings
3. MEMORIZE: Hub/Stats dict + Settings/Vocabulary/Container/SRS/Microchip wrapping
   + plural helper → ukMemorizeStrings

## DONE in this task
- Billing (PaywallView, BillingInfoView) + Parrot (ParrotPlayerView,
  ParrotWordGridView) fully wrapped and translated (ukBillingStrings, ukParrotStrings).
