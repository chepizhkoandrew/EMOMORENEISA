"""
Chat Tutor Scenario Tests — v5
================================
Focus: ADAPTIVE SIGNAL-BASED LENGTH + SOFT PRAISE FIX + NUMBERED LIST DESIGN DECISION.

Changes deployed before this run (PromptBuilder.swift v5):
  - Adaptive signal-based length replaces static level buckets:
      · One-word / emoji / "ok" → 1–2 sentences
      · Short attempt (1–3 sentences) → level-calibrated (4–5 / 5–8 / open)
      · "Explícame" / detailed question → full depth, no limit
      · Long student message → match energy and depth
  - Soft praise ban extended: "Muy bien.", "Correcto.", "Perfecto." (period, no !) now banned
  - Option A for format: numbered exercises ALLOWED for 3+ parallel items;
    markdown bold / headers / bullets still banned

Tutor model  : gpt-4.1
Analyst model: gpt-4o-mini
Audio/TTS    : DISABLED

Run: python3 tests/chat_tutor_test_v5.py
"""

import json
import re
import ssl
import sys
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Optional

_SSL_CTX = ssl.create_default_context()
try:
    import certifi
    _SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _SSL_CTX.check_hostname = False
    _SSL_CTX.verify_mode = ssl.CERT_NONE

GREEN   = "\033[92m"
RED     = "\033[91m"
YELLOW  = "\033[93m"
CYAN    = "\033[96m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
MAGENTA = "\033[95m"
RESET   = "\033[0m"

PASS = f"{GREEN}✓ PASS{RESET}"
FAIL = f"{RED}✗ FAIL{RESET}"

GLOBAL_TOKEN_LOG: list = []


# ── API key ───────────────────────────────────────────────────────────────────

def load_api_key() -> str:
    xcconfig = "EMOMORENEISA/EMOMORENEISA/EMOMORENEISA/Secrets.xcconfig"
    try:
        with open(xcconfig) as f:
            for line in f:
                if line.strip().startswith("OPENAI_API_KEY"):
                    return line.split("=", 1)[1].strip()
    except FileNotFoundError:
        pass
    import os
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        print(f"{RED}ERROR: Could not find OpenAI API key.{RESET}")
        sys.exit(1)
    return key

API_KEY       = load_api_key()
TUTOR_MODEL   = "gpt-4.1"
ANALYST_MODEL = "gpt-4o-mini"

HOLLOW_PRAISE_EXACT = [
    "¡muy bien!", "¡excelente!", "¡perfecto!", "¡fantástico!", "¡estupendo!",
    "¡genial!", "¡fenomenal!", "¡bravo!", "very good!", "excellent!",
    "muy bien!", "excelente!", "perfecto!", "fantástico!",
]

HOLLOW_PRAISE_START = re.compile(
    r"^(muy bien|correcto|perfecto|excelente|estupendo|genial|fantástico|fenomenal|bravo)[.,:\s!¡]",
    re.IGNORECASE
)

SENTENCE_BREAK = re.compile(r"[.!?]+\s+")
HOLLOW_SENTENCE_START = re.compile(
    r"(?:^|[.!?]\s+)(muy bien|correcto|perfecto|excelente|estupendo|genial|fantástico)[.,:\s!]",
    re.IGNORECASE
)

NATURAL_CONNECTORS = [
    "fíjate", "mira", "exacto", "ojo", "veamos", "fijate",
    "ojo aquí", "bueno,", "mira,", "fíjate en",
]

LIST_MARKERS = re.compile(r"^\s*[-•*]\s", re.MULTILINE)
MARKDOWN_BOLD = re.compile(r"\*\*.+?\*\*")
MARKDOWN_HEADER = re.compile(r"^#+\s", re.MULTILINE)


# ── Profiles ──────────────────────────────────────────────────────────────────

@dataclass
class WordEntry:
    word: str
    translation: str
    context: Optional[str] = None
    next_due: date = field(default_factory=date.today)

@dataclass
class ESPProfile:
    id: str                            = "test-user"
    display_name: Optional[str]        = None
    level: str                         = "beginner"
    native_language: str               = "English"
    current_study_topic: Optional[str] = None
    learning_notes: str                = ""
    word_bank: list                    = field(default_factory=list)
    weak_areas: list                   = field(default_factory=list)
    life_notes: str                    = ""
    why_learning: Optional[str]        = None
    practice_style: Optional[str]      = None
    exercise_history: list             = field(default_factory=list)

    @property
    def level_label(self) -> str:
        return {"beginner": "Beginner", "intermediate": "Intermediate", "advanced": "Advanced"}.get(self.level, "Beginner")

    @property
    def max_tokens(self) -> int:
        return {"beginner": 400, "intermediate": 600, "advanced": 800}.get(self.level, 400)

    @property
    def words_due_today(self) -> list:
        return [w for w in self.word_bank if w.next_due <= date.today()]

    @property
    def profile_digest(self) -> str:
        parts = []
        due = [w.word for w in self.words_due_today[:5]]
        if due:
            parts.append(f"Palabras para repasar hoy: {', '.join(due)}")
        if self.weak_areas:
            parts.append(f"Áreas débiles: {', '.join(self.weak_areas[:3])}")
        if self.why_learning:
            parts.append(f"Meta: {self.why_learning}")
        if self.practice_style:
            parts.append(f"Estilo: {self.practice_style}")
        if self.life_notes:
            parts.append(f"Contexto personal: {self.life_notes[:120]}")
        if self.exercise_history:
            parts.append(f"Últimos ejercicios: {', '.join(self.exercise_history[-4:])}")
        return "\n".join(parts)


# ── PromptBuilder (mirrors PromptBuilder.swift v5) ────────────────────────────

def topic_system_prompt(profile: Optional[ESPProfile], topic: Optional[str]) -> str:
    name   = (profile.display_name if profile else None) or "Student"
    level  = (profile.level_label if profile else None) or "Beginner"
    native = (profile.native_language if profile else None) or "English"
    focus  = topic or (profile.current_study_topic if profile else None) or "general Spanish"
    notes  = profile.learning_notes if (profile and profile.learning_notes) else "No previous session notes yet."
    digest = (profile.profile_digest if profile else "") or ""
    digest_block = (f"\n\n{digest}") if digest else ""

    last_exercises = (profile.exercise_history[-3:] if profile else [])
    if last_exercises:
        exercise_variety = (
            f"\n\nÚltimos tipos de ejercicio usados: {', '.join(last_exercises)}. "
            "Elige un tipo DIFERENTE a los anteriores en este turno. "
            "Rota entre: conjugación, rellena huecos, traducción inversa, corrección de errores y conversación libre."
        )
    else:
        exercise_variety = (
            "\n\nVariá los tipos de ejercicio: alterna entre explicación+ejemplo, "
            "rellena huecos, traducción inversa, corrección de errores y conversación libre."
        )

    lvl = profile.level if profile else "beginner"
    if lvl == "beginner":
        level_ceiling = "4–5 frases como máximo"
    elif lvl == "advanced":
        level_ceiling = "lo que el tema exija"
    else:
        level_ceiling = "5–8 frases como referencia"

    length_guidance = f"""Lee la señal del alumno y calibra la longitud de tu respuesta:
  • El alumno escribe algo mínimo — una sola palabra, "sí", "ok", "no sé", un emoji, o una frase muy corta sin pregunta: responde en 1–2 frases. Reconoce y da el siguiente micro-paso. No elabores más.
  • El alumno hace un intento en español (1–3 frases, con o sin errores): corrige o confirma brevemente, añade 1 ejemplo concreto y propón el siguiente paso. Longitud de referencia para {name}: {level_ceiling}.
  • El alumno pide una explicación, escribe "¿por qué?", "explícame", "no entiendo" o hace una pregunta detallada: explica en profundidad con 2–3 ejemplos, la regla y un ejercicio. Sé tan largo como el tema lo exija, sin límite artificial.
  • El alumno escribe algo largo o complejo: responde con la misma energía y profundidad — no simplifiques sin razón.
Regla de oro: si el alumno da poco, toma poco. Si el alumno da mucho, devuelve mucho. La conversación debe sentirse como un diálogo real, no como un monólogo del tutor."""

    why = (profile.why_learning if profile else None) or ""
    if why:
        frustration_line = (
            f"Si el alumno expresa frustración o dice que no entiende nada: reconócelo brevemente, "
            f"recuérdale por qué está aprendiendo (su meta: {why}), "
            "simplifica al nivel más básico posible y continúa."
        )
    else:
        frustration_line = (
            "Si el alumno expresa frustración: reconócelo brevemente en español, "
            "simplifica el ejercicio al nivel más básico posible y continúa."
        )

    return f"""Eres el Profesor Madrid — un tutor privado de español apasionado y exigente. Llevas años enseñando a {name} y conoces bien su nivel.

MARCADOR DE OBJETIVO — LEE ESTO PRIMERO:
Si el alumno pide practicar un tema nuevo O cambia de tema durante la conversación, añade OBLIGATORIAMENTE esta línea al final de tu respuesta, sin excepción:
@@GOAL: [descripción breve del nuevo enfoque, 5-8 palabras]@@
Cuándo usarlo — ejemplos exactos:
  • El alumno dice "explícame el subjuntivo" → @@GOAL: subjuntivo presente — deseos y dudas@@
  • El alumno dice "quiero practicar el pretérito" → @@GOAL: pretérito indefinido — acciones pasadas@@
  • El alumno cambia de gramática a vocabulario → @@GOAL: vocabulario de viajes y transporte@@
  • El alumno pide hablar libremente → @@GOAL: conversación libre — fluidez@@
Este marcador es invisible para {name} y se elimina automáticamente. No lo menciones nunca.

Perfil del alumno:
  - Nombre: {name}
  - Nivel: {level}
  - Lengua materna: {native}
  - Enfoque de hoy: {focus}
  - Notas anteriores: {notes}{digest_block}

REGLA PRINCIPAL: Habla casi siempre en español. Usa {native} solo para explicar una regla gramatical compleja cuando sea estrictamente necesario — máximo una o dos frases por respuesta. Todo lo demás — ejercicios, ejemplos, preguntas, correcciones — en español.

Cómo enseñas:
Empieza directamente con el ejercicio o la explicación. Sin saludos, sin frases de bienvenida, sin "¡Hola! Hoy vamos a...". El alumno ya sabe quién eres. Ve al grano.

Cuando expliques algo, muestra 2 o 3 ejemplos concretos de cómo se dice en la vida real. Da la regla, los patrones, las excepciones. Al final de cada turno, deja siempre una pregunta o tarea concreta para que el alumno practique en español.{exercise_variety}

Si el alumno comete un error, corrígelo brevemente, explica la regla en una frase, muestra la forma correcta e invítale a intentarlo de nuevo.

{frustration_line}

Sigue siempre la dirección del alumno. Si dice "explícame X" o "quiero practicar Y", hazlo inmediatamente.

PROHIBICIÓN DE ELOGIO — REGLA ABSOLUTA: Cuando el alumno acierta, la primera palabra de tu respuesta NO puede ser "Correcto", "Muy", "Bien", "Excelente", "Perfecto", "Estupendo", "Genial", "Fantástico" — ni en forma exclamativa ni normal, ni seguida de ":" ni de ".". Esto incluye "Correcto: ..." y "Muy bien. ...". Si el alumno acierta, empieza directamente con el matiz, el siguiente paso o la explicación. Si necesitas confirmar, usa un conector como "Fíjate —", "Exacto —", "Ojo —", "Mira —", "Veamos —".

Tono: directo, humano, con personalidad — como un tutor de verdad, no un robot. Usa conectores naturales cuando sean útiles: "Fíjate", "Mira", "Exacto —", "Ojo aquí", "Veamos".

Longitud: {length_guidance}

Formato: texto corrido. Sin guiones, sin asteriscos de lista, sin encabezados markdown. Los ejercicios con un solo ítem van integrados en el párrafo. Cuando hay 3 o más ítems paralelos en un ejercicio, puedes numerarlos para que el alumno sepa qué está respondiendo — pero escríbelos como los diría un tutor en voz alta, sin saltos de línea adicionales."""


# ── OpenAI call with token tracking ───────────────────────────────────────────

def call_openai(
    system_prompt: str,
    messages: list,
    user_text: str,
    temperature: float = 0.7,
    max_tokens: int = 400,
    label: str = "call",
    model: str = TUTOR_MODEL,
) -> str:
    payload = []
    if system_prompt:
        payload.append({"role": "system", "content": system_prompt})
    payload.extend(messages)
    if user_text:
        payload.append({"role": "user", "content": user_text})

    body = {
        "model": model,
        "messages": payload,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    data = json.dumps(body).encode("utf-8")
    req  = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60, context=_SSL_CTX) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            usage = result.get("usage", {})
            GLOBAL_TOKEN_LOG.append({
                "label": label,
                "model": model,
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
            })
            return result["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"OpenAI HTTP {e.code}: {e.read().decode()[:300]}")


# ── Helper functions ───────────────────────────────────────────────────────────

def hollow_praise_count(text: str) -> int:
    count = sum(1 for phrase in HOLLOW_PRAISE_EXACT if phrase in text.lower())
    count += len(HOLLOW_SENTENCE_START.findall(text))
    return count

def starts_at_sentence_with_praise(text: str) -> bool:
    return bool(HOLLOW_SENTENCE_START.search(text))

def natural_connector_count(text: str) -> int:
    t = text.lower()
    return sum(1 for c in NATURAL_CONNECTORS if c in t)

def has_bullet_lists(text: str) -> bool:
    return bool(LIST_MARKERS.search(text))

def has_numbered_lists(text: str) -> bool:
    return bool(re.search(r"^\s*\d+\.\s", text, re.MULTILINE))

def has_markdown_formatting(text: str) -> bool:
    return bool(MARKDOWN_BOLD.search(text)) or bool(MARKDOWN_HEADER.search(text))

def sentence_count(text: str) -> int:
    cleaned = re.sub(r"\.\.\.", "", text)
    sentences = re.split(r"[.!?]+", cleaned.strip())
    return len([s for s in sentences if s.strip()])

def word_count(text: str) -> int:
    return len(text.split())

def ends_with_question_or_task(text: str) -> bool:
    stripped = text.strip()
    last_200 = stripped[-200:]
    return ("?" in last_200 or
            any(w in last_200.lower() for w in
                ["escribe", "traduce", "completa", "intenta", "di", "responde",
                 "practica", "ahora tú", "ahora tu", "te toca", "transforma",
                 "conjuga", "rellena", "pon", "cambia", "termina", "elige",
                 "dime", "describe", "explica", "repite", "construye"]))

def starts_with_praise(text: str) -> bool:
    first_30 = text.strip()[:30].lower()
    starters = ["muy bien", "excelente", "perfecto", "correcto", "estupendo",
                 "fantástico", "genial", "fenomenal", "bravo"]
    return any(first_30.startswith(s) for s in starters)


# ── Test infrastructure ────────────────────────────────────────────────────────

@dataclass
class ScenarioResult:
    name: str
    passed: bool
    checks: list
    tutor_response: Optional[str] = None
    notes: str = ""


def check(label: str, condition: bool, detail: str = "") -> tuple:
    return (label, condition, detail)


def print_scenario(result: ScenarioResult):
    status = PASS if result.passed else FAIL
    print(f"\n{'─'*72}")
    print(f"{BOLD}{status}  {result.name}{RESET}")
    if result.notes:
        print(f"{DIM}  {result.notes}{RESET}")
    for (label, ok, detail) in result.checks:
        icon = f"{GREEN}✓{RESET}" if ok else f"{RED}✗{RESET}"
        print(f"  {icon} {label}", end="")
        if detail:
            print(f"  {DIM}→ {detail[:140]}{RESET}", end="")
        print()
    if result.tutor_response:
        print(f"\n{CYAN}  Tutor response:{RESET}")
        for line in result.tutor_response.strip().splitlines():
            print(f"    {line}")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 1 — Adaptive length: minimal input → 1-2 sentences
# ══════════════════════════════════════════════════════════════════════════════

def s1_adaptive_minimal_input() -> ScenarioResult:
    """
    Student sends a minimal one-word / short acknowledgment.
    Tutor MUST respond in 1–2 sentences only.
    Tests the new adaptive signal-based length rule.
    """
    profile = ESPProfile(display_name="Leo", level="intermediate", native_language="English")
    topic   = "subjunctive mood"
    sp      = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: subjunctive mood.", max_tokens=600, label="s1_opener")
    hist  = [{"role": "assistant", "content": turn1}]

    minimal_inputs = ["Sí.", "Ok.", "No sé."]
    replies = []
    for inp in minimal_inputs:
        r = call_openai(sp, hist, inp, max_tokens=300, label=f"s1_minimal_{inp[:3]}")
        hist += [{"role": "user", "content": inp}, {"role": "assistant", "content": r}]
        replies.append((inp, r))

    all_short = all(sentence_count(r) <= 4 for _, r in replies)
    any_praise = any(hollow_praise_count(r) > 0 for _, r in replies)
    any_lists  = any(has_bullet_lists(r) for _, r in replies)

    longest = max(replies, key=lambda x: len(x[1]))
    longest_sc = sentence_count(longest[1])

    checks = [
        check("All 3 minimal-input replies ≤ 4 sentences",
              all_short,
              f"sentence counts: {[sentence_count(r) for _, r in replies]} | longest: {longest[1][:120]}"),
        check("Zero hollow praise in any short reply",
              not any_praise,
              f"praise found: {any_praise}"),
        check("No bullet/dash lists in short replies",
              not any_lists,
              f"lists found: {any_lists}"),
        check("Each reply ends with next micro-step or question",
              all(ends_with_question_or_task(r) for _, r in replies),
              f"end checks: {[ends_with_question_or_task(r) for _, r in replies]}"),
    ]

    combined = "\n\n".join([f"[Student: {inp}]\n{r}" for inp, r in replies])
    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S1: Adaptive Length — Minimal Input → 1-2 Sentences",
        passed, checks,
        tutor_response=f"[Opener]\n{turn1}\n\n{combined}",
        notes="One-word 'Sí.', 'Ok.', 'No sé.' must get 1-2 sentences back, not a paragraph."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 2 — Adaptive length: "explícame" → full depth, no limit
# ══════════════════════════════════════════════════════════════════════════════

def s2_adaptive_explícame_full_depth() -> ScenarioResult:
    """
    Student says "Explícame por qué el subjuntivo existe. No entiendo nada."
    Tutor MUST give a full, detailed explanation (> 400 chars).
    Tests the no-limit signal for detailed questions.
    """
    profile = ESPProfile(display_name="Diana", level="intermediate", native_language="English",
                         weak_areas=["subjuntivo"])
    topic   = "subjunctive mood"
    sp      = topic_system_prompt(profile, topic)

    question = "Explícame por qué el subjuntivo existe y cuándo se usa. Quiero entender la lógica, no solo memorizar."
    reply    = call_openai(sp, [], question, max_tokens=700, label="s2_explicame")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    any_lists    = has_bullet_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    covers_logic = any(w in reply_lower for w in
                       ["incertidumbre", "duda", "deseo", "emoción", "hipotético",
                        "quiero que", "espero que", "es posible", "ojalá"])
    ends_well    = ends_with_question_or_task(reply)

    checks = [
        check("Full explanation (> 400 chars) — no artificial cap",
              len(reply) > 400, f"len={len(reply)}"),
        check("Covers the logic of subjunctive (uncertainty/desire/hypothesis)",
              covers_logic,
              f"concept markers found: {[w for w in ['incertidumbre','duda','deseo','hipotético'] if w in reply_lower]}"),
        check("Ends with exercise or question",
              ends_well, f"last 100: {reply[-100:]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No bullet or dash lists (prose explanation)",
              not any_lists, f"lists found: {any_lists}"),
        check("No markdown bold or headers",
              not any_markdown, f"markdown found: {any_markdown}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S2: Adaptive Length — 'Explícame' → Full Depth, No Artificial Cap",
        passed, checks,
        tutor_response=reply,
        notes="Detailed 'explícame' + 'quiero entender la lógica' must trigger long, thorough explanation."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3 — Adaptive length: student writes long → tutor matches energy
# ══════════════════════════════════════════════════════════════════════════════

def s3_adaptive_long_student_message() -> ScenarioResult:
    """
    Student writes a long, rich message (errors + questions + context).
    Tutor must match the energy: substantive, multi-part reply.
    Tests 'if the student gives a lot, give a lot back.'
    """
    profile = ESPProfile(
        display_name="Marco",
        level="intermediate",
        native_language="Italian",
        learning_notes="Marco is Italian, finds false friends between Italian and Spanish amusing.",
        life_notes="Works as a chef in Rome, visits Barcelona twice a year for work.",
    )
    topic = "past tenses — preterite vs imperfect"
    sp    = topic_system_prompt(profile, topic)

    long_student_message = (
        "Estoy confuso porque en italiano tenemos dos pasados similares — il passato prossimo y l'imperfetto — "
        "y creo que el pretérito español se parece al passato prossimo, y el imperfecto es igual en los dos idiomas. "
        "¿Es correcto? Ayer yo intenté usar el imperfecto para decir algo que pasó específicamente — "
        "'Ayer, cuando era niño, comí una paella' — y mi amigo me dijo que estaba mal. "
        "Pero no entiendo por qué, porque en italiano diría 'Ieri, da bambino, mangiavo la paella' y eso estaría bien. "
        "¿Puedes explicarme la diferencia con ejemplos de cocina o comida, porque es mi mundo?"
    )
    reply    = call_openai(sp, [], long_student_message, max_tokens=800, label="s3_long_input")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    any_lists    = has_bullet_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    is_substantive = len(reply) > 450
    covers_both    = any(w in reply_lower for w in ["pretérito", "preterito"]) and \
                     any(w in reply_lower for w in ["imperfecto", "imperfect"])
    uses_food_ctx  = any(w in reply_lower for w in
                         ["paella", "cocina", "comer", "comida", "cocinero", "cocinar",
                          "restaurante", "plato", "ingrediente"])
    ends_well      = ends_with_question_or_task(reply)

    checks = [
        check("Reply is substantive (> 450 chars) — matches long student message",
              is_substantive, f"len={len(reply)}"),
        check("Addresses both preterite and imperfect",
              covers_both, f"covers_preterite={any(w in reply_lower for w in ['pretérito','preterito'])} covers_imperfect={any(w in reply_lower for w in ['imperfecto'])}"),
        check("Uses student's context (food/cooking) in examples",
              uses_food_ctx, f"food words: {[w for w in ['paella','cocina','comer','restaurante'] if w in reply_lower]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No bullet lists (prose reply to prose question)",
              not any_lists, f"lists found: {any_lists}"),
        check("Ends with exercise or question",
              ends_well, f"last 100: {reply[-100:]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S3: Adaptive Length — Long Student Message → Tutor Matches Energy",
        passed, checks,
        tutor_response=f"[Student message (long)]\n{long_student_message}\n\n[Tutor]\n{reply}",
        notes="When student writes 120+ word message with multiple questions, tutor must match energy and depth."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4 — Short attempt with errors → brief correction + 1 example + next step
# ══════════════════════════════════════════════════════════════════════════════

def s4_short_attempt_brief_correction() -> ScenarioResult:
    """
    Beginner writes a 1-2 sentence attempt (with a grammar error).
    Tutor must: correct the error, add 1 example, propose next step.
    Should NOT write a wall of text for such a small input.
    """
    profile = ESPProfile(display_name="Anna", level="beginner", native_language="German")
    topic   = "present tense verbs"
    sp      = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: present tense.", max_tokens=400, label="s4_opener")
    hist  = [{"role": "assistant", "content": turn1}]

    attempt_with_error = "Yo soy trabajar en un oficina."
    reply = call_openai(sp, hist, attempt_with_error, max_tokens=400, label="s4_correction")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    sc           = sentence_count(reply)
    any_lists    = has_bullet_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    corrects_error = any(w in reply_lower for w in
                         ["trabajo", "trabaj", "en una", "artículo", "trabajo en"])
    ends_well    = ends_with_question_or_task(reply)

    checks = [
        check("Reply is brief (≤ 6 sentences) — beginner short attempt",
              sc <= 6, f"sentences={sc} | reply: {reply[:200]}"),
        check("Corrects the error ('soy trabajar' → 'trabajo')",
              corrects_error,
              f"correction words found: {[w for w in ['trabajo','trabaj','artículo'] if w in reply_lower]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No bullet lists",
              not any_lists, f"lists found: {any_lists}"),
        check("Ends with question or next task",
              ends_well, f"last 100: {reply[-100:]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S4: Short Attempt with Error → Brief Correction, Not Wall of Text",
        passed, checks,
        tutor_response=f"[Student: {attempt_with_error}]\n{reply}",
        notes="1-sentence student attempt. Tutor must correct briefly (≤ 6 sentences), not write an essay."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5 — Soft praise ban: period version must also be gone
# ══════════════════════════════════════════════════════════════════════════════

def s5_soft_praise_ban() -> ScenarioResult:
    """
    Student gives perfectly correct answers across multiple turns.
    The SOFT praise variants (no exclamation: 'Muy bien.', 'Correcto.',
    'Perfecto.') must also be absent — not just the ¡! versions.
    """
    profile = ESPProfile(display_name="Sam", level="intermediate", native_language="English")
    topic   = "ser vs estar"
    sp      = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: ser vs estar.", max_tokens=500, label="s5_opener")
    hist  = [{"role": "assistant", "content": turn1}]

    correct_answers = [
        "Soy estudiante. Estoy cansado.",
        "La reunión es a las tres. El café está caliente.",
        "Mi hermano es médico. Hoy está enfermo.",
    ]

    replies = []
    for ans in correct_answers:
        r = call_openai(sp, hist, ans, max_tokens=400, label=f"s5_correct_{len(replies)+1}")
        hist += [{"role": "user", "content": ans}, {"role": "assistant", "content": r}]
        replies.append(r)

    all_text = "\n".join(replies)
    praise_count = hollow_praise_count(all_text)
    praise_starts = sum(1 for r in replies if starts_with_praise(r))
    any_lists     = has_bullet_lists(all_text)
    connectors    = natural_connector_count(all_text)

    checks = [
        check("Zero hollow praise (including sentence-starting 'Muy bien.', 'Correcto.')",
              praise_count == 0,
              f"count={praise_count} | sentence-start matches: {[m.group(0)[:30] for m in [HOLLOW_SENTENCE_START.search(all_text)] if m]}"),
        check("No reply starts with praise word",
              praise_starts == 0,
              f"praise-starting replies: {praise_starts}"),
        check("At least 1 natural connector across 3 replies",
              connectors >= 1, f"connectors={connectors}"),
        check("No bullet lists",
              not any_lists, f"lists found: {any_lists}"),
        check("All 3 replies end with task or question",
              all(ends_with_question_or_task(r) for r in replies),
              f"end checks: {[ends_with_question_or_task(r) for r in replies]}"),
    ]

    combined = "\n\n".join([f"[Student: {ans}]\n{r}" for ans, r in zip(correct_answers, replies)])
    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S5: Soft Praise Ban — Period Version ('Muy bien.') Also Gone",
        passed, checks,
        tutor_response=combined,
        notes="Student gives 3 correct answers. Must never open with 'Muy bien.', 'Correcto.', 'Perfecto.' (any form)."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6 — Advanced multi-item exercises: numbered list IS now allowed
# ══════════════════════════════════════════════════════════════════════════════

def s6_advanced_numbered_exercise_allowed() -> ScenarioResult:
    """
    Advanced student. Tutor gives multi-item transformation exercise.
    Per Option A: numbered lists ARE allowed for 3+ parallel items.
    Markdown bold/headers/bullets are still banned.
    Content must be C1-level quality.
    """
    profile = ESPProfile(
        display_name="Isabelle",
        level="advanced",
        native_language="French",
        learning_notes="B2+ student pushing into C1. Comfortable with subjunctive. Now targeting complex conditionals and register.",
        weak_areas=["conditional perfect", "past subjunctive in conditionals"],
    )
    topic = "complex conditional sentences (si clauses at C1)"
    sp    = topic_system_prompt(profile, topic)

    reply    = call_openai(sp, [],
                           "Dame un ejercicio desafiante con cuatro frases para transformar. Quiero practicar el condicional perfecto.",
                           max_tokens=800, label="s6_advanced_exercise")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    any_bullets  = has_bullet_lists(reply)
    any_numbered = has_numbered_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    covers_c1    = any(w in reply_lower for w in
                       ["habría", "hubiera", "habría sido", "si hubiera", "condicional",
                        "perfecto", "si hubieras", "habrías"])
    ends_well    = ends_with_question_or_task(reply)
    is_deep      = len(reply) > 350

    checks = [
        check("Response is deep and C1-level (> 350 chars)",
              is_deep, f"len={len(reply)}"),
        check("Uses C1-level conditional perfect forms",
              covers_c1,
              f"C1 forms found: {[w for w in ['habría','hubiera','si hubiera','habrías'] if w in reply_lower]}"),
        check("Numbered list IS present (Option A — allowed for 3+ parallel items)",
              any_numbered,
              f"numbered items found: {any_numbered} | reply snippet: {reply[:300]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No bullet/dash lists (numbered ok, bullets not ok)",
              not any_bullets, f"bullets found: {any_bullets}"),
        check("No markdown bold or headers",
              not any_markdown, f"markdown found: {any_markdown}"),
        check("Ends with task or question",
              ends_well, f"last 100: {reply[-100:]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S6: Advanced Multi-Item Exercise — Numbered Lists Now Allowed (Option A)",
        passed, checks,
        tutor_response=reply,
        notes="Option A: numbered exercises are OK for 3+ parallel items. Bullets/markdown still banned."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 7 — Frustration: personal motivation referenced naturally
# ══════════════════════════════════════════════════════════════════════════════

def s7_frustration_references_motivation() -> ScenarioResult:
    """
    Student expresses frustration mid-lesson.
    Tutor must acknowledge, reference the student's 'why_learning',
    simplify and continue. No hollow praise. Stays in Spanish.
    (Reprise of v4 S6 to confirm it still works after v5 prompt changes.)
    """
    profile = ESPProfile(
        display_name="Carlos",
        level="beginner",
        native_language="English",
        why_learning="I want to talk to my wife's family in Mexico City",
    )
    topic = "preterite tense"
    sp    = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: preterite tense.", max_tokens=400, label="s7_t1")
    hist  = [{"role": "assistant", "content": turn1}]

    frustration = "I give up. This is impossible. I've been trying for months and I still can't remember anything. Languages just aren't for me."
    reply       = call_openai(sp, hist, frustration, max_tokens=500, label="s7_frustrated")
    reply_lower = reply.lower()

    praise         = hollow_praise_count(reply)
    any_lists      = has_bullet_lists(reply)
    references_why = any(w in reply_lower for w in
                         ["mexico", "esposa", "familia", "wife", "family",
                          "meta", "objetivo", "razón", "quieres", "hablar"])
    acknowledges   = any(w in reply_lower for w in
                         ["entiendo", "comprendo", "normal", "difícil",
                          "tranquilo", "poco a poco", "no te preocupes"])
    simplifies     = any(w in reply_lower for w in
                         ["simple", "sencillo", "básico", "empezamos", "primero",
                          "una sola", "solo una", "paso a paso", "más fácil"])
    stays_spanish  = sum(1 for w in ["que", "es", "en", "el", "la", "un", "de", "con", "por"]
                         if w in reply_lower) >= 5

    checks = [
        check("Tutor acknowledges the frustration",
              acknowledges, f"markers: {[w for w in ['entiendo','comprendo','normal','tranquilo'] if w in reply_lower]}"),
        check("Personal motivation referenced (Mexico/family/meta)",
              references_why,
              f"motivation words: {[w for w in ['mexico','familia','esposa','meta','wife'] if w in reply_lower]}"),
        check("Tutor simplifies or offers easier path",
              simplifies, f"markers: {[w for w in ['simple','básico','empezamos','fácil'] if w in reply_lower]}"),
        check("Response stays predominantly in Spanish",
              stays_spanish, f"Spanish function word count ≥ 5"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S7: Frustration Handler — Personal Motivation Referenced",
        passed, checks,
        tutor_response=f"[Student: {frustration}]\n{reply}",
        notes="Student gives up. Tutor must weave in 'Mexico/esposa/familia' and simplify."
    )


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 8 — Mixed-signal multi-turn: length calibrates per turn
# ══════════════════════════════════════════════════════════════════════════════

def s8_mixed_signal_length_calibration() -> ScenarioResult:
    """
    4-turn conversation where student alternates between minimal and detailed inputs.
    Tutor must calibrate length per turn:
      Turn 1 student: "Sí." → short tutor reply
      Turn 2 student: long + detailed → rich tutor reply
      Turn 3 student: "Ok" → short tutor reply
      Turn 4 student: "Explícame eso más" → detailed tutor reply
    """
    profile = ESPProfile(display_name="Nora", level="intermediate", native_language="English")
    topic   = "past tenses — preterite vs imperfect"
    sp      = topic_system_prompt(profile, topic)

    opener = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: preterite vs imperfect.", max_tokens=600, label="s8_opener")
    hist   = [{"role": "assistant", "content": opener}]

    t1_input = "Sí."
    t1_reply = call_openai(sp, hist, t1_input, max_tokens=300, label="s8_t1_short")
    hist += [{"role": "user", "content": t1_input}, {"role": "assistant", "content": t1_reply}]

    t2_input = ("Creo que entiendo la diferencia básica — el pretérito es para acciones completas y el imperfecto "
                "para acciones en progreso o habituales. Pero me confundo cuando hay dos acciones en la misma frase, "
                "como 'estaba comiendo cuando sonó el teléfono'. ¿Puedes explicarme cuándo se mezclan los dos y por qué?")
    t2_reply = call_openai(sp, hist, t2_input, max_tokens=700, label="s8_t2_long")
    hist += [{"role": "user", "content": t2_input}, {"role": "assistant", "content": t2_reply}]

    t3_input = "Ok."
    t3_reply = call_openai(sp, hist, t3_input, max_tokens=300, label="s8_t3_short")
    hist += [{"role": "user", "content": t3_input}, {"role": "assistant", "content": t3_reply}]

    t4_input = "Explícame más sobre las acciones de fondo en el imperfecto. No entiendo bien cuándo una acción es 'de fondo'."
    t4_reply = call_openai(sp, hist, t4_input, max_tokens=700, label="s8_t4_explain")

    t1_short  = sentence_count(t1_reply) <= 3
    t2_rich   = len(t2_reply) > 350
    t3_short  = sentence_count(t3_reply) <= 3
    t4_rich   = len(t4_reply) > 300

    praise_total = sum(hollow_praise_count(r) for r in [t1_reply, t2_reply, t3_reply, t4_reply])
    any_bullets  = any(has_bullet_lists(r) for r in [t1_reply, t2_reply, t3_reply, t4_reply])
    any_markdown = any(has_markdown_formatting(r) for r in [t1_reply, t2_reply, t3_reply, t4_reply])

    checks = [
        check("Turn 1 'Sí.' → short reply (≤ 3 sentences)",
              t1_short, f"sentences={sentence_count(t1_reply)} | {t1_reply[:120]}"),
        check("Turn 2 long question → rich reply (> 350 chars)",
              t2_rich, f"len={len(t2_reply)} | {t2_reply[:120]}"),
        check("Turn 3 'Ok.' → short reply (≤ 3 sentences)",
              t3_short, f"sentences={sentence_count(t3_reply)} | {t3_reply[:120]}"),
        check("Turn 4 'Explícame' → detailed reply (> 300 chars)",
              t4_rich, f"len={len(t4_reply)} | {t4_reply[:120]}"),
        check("Zero hollow praise across all 4 turns",
              praise_total == 0, f"total praise phrases: {praise_total}"),
        check("No bullet/dash lists in any turn",
              not any_bullets, f"bullets found: {any_bullets}"),
        check("No markdown formatting in any turn",
              not any_markdown, f"markdown found: {any_markdown}"),
    ]

    combined = (
        f"[Opener]\n{opener}\n\n"
        f"[T1 Student: '{t1_input}']\n{t1_reply}\n\n"
        f"[T2 Student: '{t2_input[:80]}...']\n{t2_reply}\n\n"
        f"[T3 Student: '{t3_input}']\n{t3_reply}\n\n"
        f"[T4 Student: '{t4_input[:60]}...']\n{t4_reply}"
    )
    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        "S8: Mixed-Signal Multi-Turn — Length Calibrates Per Turn",
        passed, checks,
        tutor_response=combined,
        notes="Alternating minimal/detailed inputs. Tutor must give short→long→short→long responses accordingly."
    )


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def print_token_summary():
    if not GLOBAL_TOKEN_LOG:
        return
    print(f"\n{'═'*72}")
    print(f"{BOLD}TOKEN USAGE SUMMARY{RESET}")
    print(f"{'─'*72}")

    tutor_p = sum(e["prompt_tokens"] for e in GLOBAL_TOKEN_LOG if e["model"] == TUTOR_MODEL)
    tutor_c = sum(e["completion_tokens"] for e in GLOBAL_TOKEN_LOG if e["model"] == TUTOR_MODEL)
    analyst_p = sum(e["prompt_tokens"] for e in GLOBAL_TOKEN_LOG if e["model"] == ANALYST_MODEL)
    analyst_c = sum(e["completion_tokens"] for e in GLOBAL_TOKEN_LOG if e["model"] == ANALYST_MODEL)
    total     = sum(e["total_tokens"] for e in GLOBAL_TOKEN_LOG)
    n_calls   = len(GLOBAL_TOKEN_LOG)

    TUTOR_INPUT_PRICE    = 2.00 / 1_000_000
    TUTOR_OUTPUT_PRICE   = 8.00 / 1_000_000
    ANALYST_INPUT_PRICE  = 0.15 / 1_000_000
    ANALYST_OUTPUT_PRICE = 0.60 / 1_000_000

    cost = (tutor_p * TUTOR_INPUT_PRICE + tutor_c * TUTOR_OUTPUT_PRICE +
            analyst_p * ANALYST_INPUT_PRICE + analyst_c * ANALYST_OUTPUT_PRICE)

    print(f"  Tutor  ({TUTOR_MODEL}): {tutor_p:,} prompt + {tutor_c:,} completion")
    print(f"  Analyst ({ANALYST_MODEL}): {analyst_p:,} prompt + {analyst_c:,} completion")
    print(f"  Total tokens : {total:,} across {n_calls} calls")
    print(f"  Estimated cost: ${cost:.4f}")

    print(f"\n{'─'*72}")
    print(f"{BOLD}PER-CALL BREAKDOWN{RESET}")
    print(f"{'─'*72}")
    for entry in GLOBAL_TOKEN_LOG:
        print(f"  {entry['label']:<35} {entry['prompt_tokens']:>6}p  {entry['completion_tokens']:>5}c  {entry['total_tokens']:>6}t  [{entry['model']}]")


def main():
    scenarios = [
        s1_adaptive_minimal_input,
        s2_adaptive_explícame_full_depth,
        s3_adaptive_long_student_message,
        s4_short_attempt_brief_correction,
        s5_soft_praise_ban,
        s6_advanced_numbered_exercise_allowed,
        s7_frustration_references_motivation,
        s8_mixed_signal_length_calibration,
    ]

    results = []
    print(f"\n{BOLD}{'═'*72}{RESET}")
    print(f"{BOLD}SPANISH TUTOR BACKEND TESTS — v5{RESET}")
    print(f"{BOLD}Focus: Adaptive Length · Soft Praise Ban · Numbered Exercise Design{RESET}")
    print(f"{BOLD}{'═'*72}{RESET}")
    print(f"  Tutor model  : {TUTOR_MODEL}")
    print(f"  Analyst model: {ANALYST_MODEL}")
    print(f"  TTS/Audio    : DISABLED")
    print(f"  Scenarios    : {len(scenarios)}")

    for fn in scenarios:
        print(f"\n{YELLOW}Running {fn.__name__}...{RESET}")
        result = fn()
        results.append(result)
        print_scenario(result)

    passed_count = sum(1 for r in results if r.passed)
    total_count  = len(results)

    print(f"\n{'═'*72}")
    print(f"{BOLD}RESULTS: {passed_count}/{total_count} passed{RESET}")
    for r in results:
        status = PASS if r.passed else FAIL
        print(f"  {status}  {r.name}")

    print_token_summary()


if __name__ == "__main__":
    main()
