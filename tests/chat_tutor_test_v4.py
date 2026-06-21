"""
Chat Tutor Scenario Tests — v4
================================
Focus: TONE OF VOICE and RESPONSE LENGTH calibration.

New prompt features tested:
  - No hollow praise ("¡Muy bien!", "¡Excelente!", "¡Perfecto!", "¡Fantástico!")
  - Natural connectors ("Fíjate", "Mira", "Exacto", "Ojo", "Veamos")
  - No numbered/bulleted lists — exercises in running prose
  - Length calibration: beginner ≤ 5 sentences, intermediate 5–8, advanced richer
  - Simple question → short answer (≤ 200 chars)
  - Motivation referenced during frustration
  - Default exercise variety even on first session (no prior history)

Tutor model  : gpt-4.1
Analyst model: gpt-4o-mini
Audio/TTS    : DISABLED

Run: python3 tests/chat_tutor_test_v4.py
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

HOLLOW_PRAISE = [
    "¡muy bien!", "¡excelente!", "¡perfecto!", "¡fantástico!", "¡estupendo!",
    "¡genial!", "¡fenomenal!", "¡bravo!", "very good!", "excellent!",
    "muy bien!", "excelente!", "perfecto!", "fantástico!",
]

NATURAL_CONNECTORS = [
    "fíjate", "mira", "exacto", "ojo", "veamos", "fijate",
    "ojo aquí", "bueno,", "mira,", "fíjate en",
]

LIST_MARKERS = re.compile(r"^\s*(\d+\.|[-•*])\s", re.MULTILINE)
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


# ── Updated PromptBuilder (mirrors PromptBuilder.swift v4) ────────────────────

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
        length_guidance = ("Principiante: máximo 4–5 frases por turno. Simple, directo, sin abrumar. "
                           "Si el alumno hace una pregunta sencilla, responde en 1–2 frases y da un ejercicio corto.")
    elif lvl == "advanced":
        length_guidance = ("Avanzado: lo que el tema requiera. Puede ser más largo si la gramática es compleja. "
                           "Siempre termina con un ejercicio o pregunta.")
    else:
        length_guidance = "Intermedio: 5–8 frases por turno. Explicación breve + 1–2 ejemplos reales + ejercicio concreto."

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

Tono: directo, humano, con personalidad — como un tutor de verdad, no un robot. Evita el elogio vacío ("¡Muy bien!", "¡Excelente!", "¡Perfecto!", "¡Fantástico!"). Si el alumno acierta, confirma en una palabra o dos y continúa inmediatamente. Usa conectores naturales cuando sean útiles: "Fíjate", "Mira", "Exacto —", "Ojo aquí", "Veamos".

Longitud: {length_guidance}

Formato: texto corrido. Sin listas numeradas, sin guiones, sin markdown, sin asteriscos, sin encabezados. Los ejercicios van integrados en el párrafo, escritos como los diría un tutor en voz alta."""


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
    t = text.lower()
    return sum(1 for phrase in HOLLOW_PRAISE if phrase in t)

def natural_connector_count(text: str) -> int:
    t = text.lower()
    return sum(1 for c in NATURAL_CONNECTORS if c in t)

def has_markdown_lists(text: str) -> bool:
    return bool(LIST_MARKERS.search(text))

def has_markdown_formatting(text: str) -> bool:
    return bool(MARKDOWN_BOLD.search(text)) or bool(MARKDOWN_HEADER.search(text))

def sentence_count(text: str) -> int:
    sentences = re.split(r"[.!?]+", text.strip())
    return len([s for s in sentences if s.strip()])

def ends_with_question_or_task(text: str) -> bool:
    stripped = text.strip()
    last_200 = stripped[-200:]
    return ("?" in last_200 or
            any(w in last_200.lower() for w in
                ["escribe", "traduce", "completa", "intenta", "di", "responde",
                 "practica", "ahora tú", "ahora tu", "te toca"]))


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
# SCENARIO 1 — Hollow praise trap: correct answer must not trigger ¡Muy bien!
# ══════════════════════════════════════════════════════════════════════════════

def s1_no_hollow_praise() -> ScenarioResult:
    """
    Student gives a correct answer. Tutor must NOT respond with
    hollow praise. Should confirm briefly and move on or deepen.
    Three consecutive correct answers tested.
    """
    profile = ESPProfile(display_name="Mia", level="intermediate", native_language="English")
    topic   = "preterite tense"
    sp      = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: preterite tense.", max_tokens=500, label="s1_t1")
    hist  = [{"role": "assistant", "content": turn1}]

    correct_a = "Ayer yo comí una pizza y bebí agua."
    reply_a   = call_openai(sp, hist, correct_a, max_tokens=400, label="s1_correct_a")
    hist     += [{"role": "user", "content": correct_a}, {"role": "assistant", "content": reply_a}]

    correct_b = "El fin de semana pasado fui al cine con mis amigos y vimos una película."
    reply_b   = call_openai(sp, hist, correct_b, max_tokens=400, label="s1_correct_b")
    hist     += [{"role": "user", "content": correct_b}, {"role": "assistant", "content": reply_b}]

    correct_c = "Estudié español durante dos horas ayer."
    reply_c   = call_openai(sp, hist, correct_c, max_tokens=400, label="s1_correct_c")

    combined = "\n\n".join([
        f"[Student: {correct_a}]\n{reply_a}",
        f"[Student: {correct_b}]\n{reply_b}",
        f"[Student: {correct_c}]\n{reply_c}",
    ])

    all_replies = "\n".join([reply_a, reply_b, reply_c])
    praise = hollow_praise_count(all_replies)
    connectors = natural_connector_count(all_replies)
    any_lists = has_markdown_lists(all_replies)
    any_markdown = has_markdown_formatting(all_replies)

    checks = [
        check("Zero hollow praise across 3 correct answers",
              praise == 0,
              f"count={praise} | first match context: {[p for p in HOLLOW_PRAISE if p in all_replies.lower()][:3]}"),
        check("At least 1 natural connector used",
              connectors >= 1,
              f"count={connectors}"),
        check("No markdown lists (numbered or bulleted)",
              not any_lists,
              f"list markers found: {any_lists}"),
        check("No markdown bold or headers",
              not any_markdown,
              f"markdown found: {any_markdown}"),
        check("Each reply ends with question or task",
              ends_with_question_or_task(reply_a) and ends_with_question_or_task(reply_b),
              f"a={ends_with_question_or_task(reply_a)} b={ends_with_question_or_task(reply_b)}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S1: No Hollow Praise — Three Correct Answers", passed, checks,
                          tutor_response=combined,
                          notes="3 correct student answers. Must confirm briefly and push forward, not celebrate.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 2 — Simple question gets a short answer
# ══════════════════════════════════════════════════════════════════════════════

def s2_short_answer_for_simple_question() -> ScenarioResult:
    """
    Student asks a simple yes/no or one-fact question.
    Reply must be ≤ 200 chars and end with a follow-up or task.
    Tested with two different simple questions.
    """
    profile = ESPProfile(display_name="Tomas", level="intermediate", native_language="English")
    topic   = "irregular verbs"
    sp      = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: irregular verbs.", max_tokens=500, label="s2_t1")
    hist  = [{"role": "assistant", "content": turn1}]

    q_simple_a = "¿'Fui' es la forma irregular de 'ir' en pretérito?"
    reply_a    = call_openai(sp, hist, q_simple_a, max_tokens=200, label="s2_simple_a")

    hist += [{"role": "user", "content": q_simple_a}, {"role": "assistant", "content": reply_a}]
    q_simple_b = "¿'Ver' tiene una forma irregular en pretérito?"
    reply_b    = call_openai(sp, hist, q_simple_b, max_tokens=200, label="s2_simple_b")

    praise_a = hollow_praise_count(reply_a)
    praise_b = hollow_praise_count(reply_b)
    any_lists = has_markdown_lists(reply_a + reply_b)

    checks = [
        check("Simple question A: reply ≤ 250 chars",
              len(reply_a) <= 250,
              f"len={len(reply_a)} | reply='{reply_a[:120]}'"),
        check("Simple question B: reply ≤ 250 chars",
              len(reply_b) <= 250,
              f"len={len(reply_b)} | reply='{reply_b[:120]}'"),
        check("No hollow praise in either short reply",
              praise_a + praise_b == 0,
              f"praise_count={praise_a + praise_b}"),
        check("No list formatting in short replies",
              not any_lists,
              f"lists found: {any_lists}"),
        check("Both replies end with question or task",
              ends_with_question_or_task(reply_a) and ends_with_question_or_task(reply_b),
              f"a={ends_with_question_or_task(reply_a)} b={ends_with_question_or_task(reply_b)}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S2: Simple Question → Short, Focused Answer", passed, checks,
                          tutor_response=f"Q: {q_simple_a}\nA: {reply_a}\n\nQ: {q_simple_b}\nA: {reply_b}",
                          notes="Yes/no questions must get concise answers, not full essay responses.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3 — Complex topic gets proportionate depth (intermediate)
# ══════════════════════════════════════════════════════════════════════════════

def s3_complex_topic_depth_intermediate() -> ScenarioResult:
    """
    Intermediate student asks for a full explanation of ser vs estar.
    Reply must be substantial (> 350 chars), cover both verbs with examples,
    end with an exercise, and use NO numbered lists.
    """
    profile = ESPProfile(display_name="Elena", level="intermediate", native_language="English")
    topic   = "ser vs estar"
    sp      = topic_system_prompt(profile, topic)

    reply = call_openai(sp, [], "Explícame cuándo usar ser y cuándo usar estar. Quiero entender la diferencia.", max_tokens=600, label="s3_explanation")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    any_lists    = has_markdown_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    covers_both  = "ser" in reply_lower and "estar" in reply_lower
    has_examples = any(w in reply_lower for w in ["soy", "estoy", "es", "está", "somos", "estamos"])
    ends_well    = ends_with_question_or_task(reply)

    checks = [
        check("Response is substantial (> 350 chars)",
              len(reply) > 350, f"len={len(reply)}"),
        check("Covers both ser and estar with examples",
              covers_both and has_examples,
              f"ser={'ser' in reply_lower} estar={'estar' in reply_lower} examples={has_examples}"),
        check("Ends with exercise or question",
              ends_well, f"last 100: {reply[-100:]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No numbered/bulleted lists",
              not any_lists, f"lists found: {any_lists}"),
        check("No markdown bold or headers",
              not any_markdown, f"markdown found: {any_markdown}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S3: Complex Topic → Full Explanation, No Lists (Intermediate)", passed, checks,
                          tutor_response=reply,
                          notes="Full ser vs estar explanation. Must be prose, not a numbered breakdown.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4 — Beginner brevity: lesson opener must not overwhelm
# ══════════════════════════════════════════════════════════════════════════════

def s4_beginner_brevity() -> ScenarioResult:
    """
    A complete beginner. Lesson opener + first student response.
    Each tutor turn must be short (≤ 5 sentences) and use plain prose.
    """
    profile = ESPProfile(display_name="Jake", level="beginner", native_language="English")
    topic   = "basic greetings and introductions"
    sp      = topic_system_prompt(profile, topic)

    opener = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: basic greetings.", max_tokens=400, label="s4_opener")
    hist   = [{"role": "assistant", "content": opener}]

    student_attempt = "Hola, me llamo Jake. Soy de Estados Unidos."
    reply2 = call_openai(sp, hist, student_attempt, max_tokens=400, label="s4_reply2")

    opener_sentences = sentence_count(opener)
    reply2_sentences = sentence_count(reply2)
    praise           = hollow_praise_count(opener + reply2)
    any_lists        = has_markdown_lists(opener + reply2)
    any_markdown     = has_markdown_formatting(opener + reply2)

    checks = [
        check("Opener ≤ 6 sentences (beginner level, not overwhelming)",
              opener_sentences <= 6, f"sentences={opener_sentences} | opener: {opener[:200]}"),
        check("Second reply ≤ 6 sentences",
              reply2_sentences <= 6, f"sentences={reply2_sentences}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No numbered or bulleted lists",
              not any_lists, f"lists found: {any_lists}"),
        check("No markdown bold or headers",
              not any_markdown, f"markdown found: {any_markdown}"),
        check("Both turns end with question or task",
              ends_with_question_or_task(opener) and ends_with_question_or_task(reply2),
              f"opener={ends_with_question_or_task(opener)} reply2={ends_with_question_or_task(reply2)}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S4: Beginner Brevity — No Wall of Text", passed, checks,
                          tutor_response=f"[Opener]\n{opener}\n\n[Student: {student_attempt}]\n{reply2}",
                          notes="Beginner must get short, focused turns — not a grammar textbook.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5 — Advanced student: depth and quality, still no lists
# ══════════════════════════════════════════════════════════════════════════════

def s5_advanced_depth_no_lists() -> ScenarioResult:
    """
    Advanced B2/C1 student. Rich subjunctive explanation requested.
    Must be deep (> 400 chars), prose-only, no lists, ends with challenge.
    """
    profile = ESPProfile(
        display_name="Sofía",
        level="advanced",
        native_language="French",
        learning_notes="Handles B2 grammar well. Wants to push into C1: nuance, register, conditionals.",
        weak_areas=["subjuntivo imperfecto", "conditional perfect"],
    )
    topic = "uses of subjunctive imperfect in complex sentences"
    sp    = topic_system_prompt(profile, topic)

    reply    = call_openai(sp, [], "Empieza ya. Sin saludo. Quiero un ejercicio desafiante de subjuntivo imperfecto.", max_tokens=800, label="s5_advanced")
    reply_lower = reply.lower()

    praise       = hollow_praise_count(reply)
    any_lists    = has_markdown_lists(reply)
    any_markdown = has_markdown_formatting(reply)
    covers_subjuntivo = any(w in reply_lower for w in
                             ["subjuntivo", "imperfecto", "subjuntivo imperfecto", "tuviera", "fuera",
                              "pudiera", "quisiera", "dijera"])
    ends_well    = ends_with_question_or_task(reply)
    connectors   = natural_connector_count(reply)

    checks = [
        check("Response is deep (> 400 chars)",
              len(reply) > 400, f"len={len(reply)}"),
        check("Covers subjuntivo imperfecto with actual forms",
              covers_subjuntivo, f"key forms in reply: {['tuviera','fuera','pudiera'] if covers_subjuntivo else 'NONE'}"),
        check("Ends with challenge exercise or question",
              ends_well, f"last 100: {reply[-100:]}"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No numbered or bulleted lists (exercises in prose)",
              not any_lists, f"lists found: {any_lists}"),
        check("No markdown formatting",
              not any_markdown, f"markdown found: {any_markdown}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S5: Advanced Depth — Prose Exercise, No Markdown Lists", passed, checks,
                          tutor_response=reply,
                          notes="Advanced B2/C1. Must be rich and challenging. Exercises must be in flowing prose.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6 — Frustration + motivation: why_learning referenced
# ══════════════════════════════════════════════════════════════════════════════

def s6_frustration_with_motivation() -> ScenarioResult:
    """
    Student expresses frustration. Tutor must:
    1. Acknowledge briefly
    2. Reference the student's personal motivation (why_learning)
    3. Simplify and continue
    No hollow praise. Stays in Spanish.
    """
    profile = ESPProfile(
        display_name="Carlos",
        level="beginner",
        native_language="English",
        why_learning="I want to talk to my wife's family in Mexico City",
    )
    topic = "preterite tense"
    sp    = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: preterite tense.", max_tokens=400, label="s6_t1")
    hist  = [{"role": "assistant", "content": turn1}]

    frustration = "I give up. I can't remember anything and this is just too hard. I'm not good at languages at all."
    reply       = call_openai(sp, hist, frustration, max_tokens=500, label="s6_frustrated")
    reply_lower = reply.lower()

    praise             = hollow_praise_count(reply)
    any_lists          = has_markdown_lists(reply)
    references_why     = any(w in reply_lower for w in
                              ["mexico", "esposa", "familia", "wife", "family", "ciudad",
                               "meta", "objetivo", "razón", "quieres", "hablar"])
    acknowledges       = any(w in reply_lower for w in
                              ["entiendo", "comprendo", "normal", "difícil", "es difícil",
                               "no te preocupes", "tranquilo", "poco a poco"])
    simplifies         = any(w in reply_lower for w in
                              ["simple", "sencillo", "básico", "empezamos", "primero",
                               "una sola", "solo una", "paso a paso", "más fácil", "fácil"])
    stays_in_spanish   = sum(1 for w in ["que", "es", "en", "el", "la", "un", "de", "con", "por"]
                             if w in reply_lower) >= 5

    checks = [
        check("Tutor acknowledges the frustration",
              acknowledges, f"acknowledge markers found: {acknowledges}"),
        check("Tutor references personal motivation (Mexico/family/meta)",
              references_why,
              f"motivation words found: {[w for w in ['mexico','familia','esposa','meta'] if w in reply_lower]} | reply: {reply[:200]}"),
        check("Tutor simplifies or offers easier path",
              simplifies, f"simplification markers found: {simplifies}"),
        check("Response stays predominantly in Spanish",
              stays_in_spanish, f"Spanish word density OK"),
        check("Zero hollow praise",
              praise == 0, f"praise_count={praise}"),
        check("No numbered or bulleted lists",
              not any_lists, f"lists found: {any_lists}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S6: Frustration → Motivation Referenced + Simplification", passed, checks,
                          tutor_response=f"[T1]\n{turn1}\n\n[Frustrated student]\n{reply}",
                          notes="why_learning in profile: 'talk to wife's family in Mexico City'. Must be referenced.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 7 — First-session student: default exercise variety
# ══════════════════════════════════════════════════════════════════════════════

def s7_first_session_variety() -> ScenarioResult:
    """
    Student has no exercise_history (first session).
    New prompt injects a default variety nudge.
    Run 3 consecutive turns — analyst should detect 2+ different exercise types.
    """
    profile = ESPProfile(
        display_name="Noa",
        level="beginner",
        native_language="English",
        exercise_history=[],
    )
    topic   = "numbers and basic counting"
    sp      = topic_system_prompt(profile, topic)
    history = []
    exercise_types = []

    turns = [
        "Empieza ya. Sin saludo. Practicando: numbers.",
        "Entiendo. ¿Puedes darme un ejercicio?",
        "Dos más tres son... ¿cinco?",
    ]

    for i, user_msg in enumerate(turns):
        reply = call_openai(sp, history, user_msg, max_tokens=400, label=f"s7_t{i+1}")
        history.append({"role": "user", "content": user_msg})
        history.append({"role": "assistant", "content": reply})

        analyst_prompt = f"""Analyze this Spanish tutoring exchange and return ONLY JSON.
Tutor: {reply}
{{"exercise_type_delivered": "conjugation_drill|gap_fill|error_correction|back_translation|recall|generative_use|minimal_pairs|chunk_memorize|free_conversation|null"}}"""
        raw = call_openai("", [], analyst_prompt, temperature=0, max_tokens=80,
                          label=f"s7_t{i+1}_analyst", model=ANALYST_MODEL)
        cleaned = raw.strip().lstrip("```json").lstrip("```").rstrip("```").strip()
        try:
            parsed = json.loads(cleaned)
            ex_type = parsed.get("exercise_type_delivered", "null")
        except Exception:
            ex_type = "null"
        exercise_types.append(ex_type)

    all_replies  = "\n".join(h["content"] for h in history if h["role"] == "assistant")
    praise       = hollow_praise_count(all_replies)
    any_lists    = has_markdown_lists(all_replies)
    any_markdown = has_markdown_formatting(all_replies)
    distinct     = len(set(t for t in exercise_types if t not in (None, "null")))

    checks = [
        check("3 turns complete",
              len(history) == 6, f"turns={len(history)//2}"),
        check("Default variety nudge fired (no exercise_history): 2+ distinct types across 3 turns",
              distinct >= 2,
              f"types={exercise_types}, distinct={distinct}"),
        check("Zero hollow praise across all 3 turns",
              praise == 0, f"praise_count={praise}"),
        check("No list formatting across all 3 turns",
              not any_lists, f"lists found: {any_lists}"),
        check("No markdown across all 3 turns",
              not any_markdown, f"markdown found: {any_markdown}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S7: First Session — Default Exercise Variety", passed, checks,
                          tutor_response="\n\n".join(
                              f"[T{i+1}] {h['content'][:200]}" for i, h in enumerate(history) if h["role"] == "assistant"
                          ),
                          notes="No prior exercise_history → new default variety nudge should produce ≥2 types.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 8 — Format compliance: multi-turn, no lists ever
# ══════════════════════════════════════════════════════════════════════════════

def s8_format_compliance_multi_turn() -> ScenarioResult:
    """
    5-turn lesson on a grammar-heavy topic (verb conjugation).
    Every single tutor turn must be format-compliant:
    - No numbered lists
    - No markdown bold
    - No hollow praise
    Tests that the format instruction holds across multiple turns,
    even when exercises require structure.
    """
    profile = ESPProfile(display_name="Lena", level="intermediate", native_language="English")
    topic   = "present subjunctive — wishes and recommendations"
    sp      = topic_system_prompt(profile, topic)
    history = []

    turns = [
        "Empieza ya. Sin saludo. Practicando: present subjunctive.",
        "¿Puedes darme más ejemplos con verbos de deseo como 'querer' y 'esperar'?",
        "Quiero que mi amigo venga a la fiesta. ¿Es correcto?",
        "¿Cómo digo 'I recommend that she studies more'?",
        "Recomiendo que ella estudie más. ¿Perfecto?",
    ]

    violations = []
    all_replies = []

    for i, user_msg in enumerate(turns):
        reply = call_openai(sp, history, user_msg, max_tokens=500, label=f"s8_t{i+1}")
        history.append({"role": "user", "content": user_msg})
        history.append({"role": "assistant", "content": reply})
        all_replies.append(reply)

        turn_praise   = hollow_praise_count(reply)
        turn_lists    = has_markdown_lists(reply)
        turn_markdown = has_markdown_formatting(reply)
        if turn_praise > 0:
            violations.append(f"T{i+1}: hollow_praise={turn_praise}")
        if turn_lists:
            violations.append(f"T{i+1}: list_markers_found")
        if turn_markdown:
            violations.append(f"T{i+1}: markdown_found")

    combined_text = "\n".join(all_replies)
    total_praise   = hollow_praise_count(combined_text)
    total_lists    = has_markdown_lists(combined_text)
    total_markdown = has_markdown_formatting(combined_text)
    all_end_well   = all(ends_with_question_or_task(r) for r in all_replies)
    connectors     = natural_connector_count(combined_text)

    checks = [
        check("5 turns completed",
              len(history) == 10, f"turns={len(history)//2}"),
        check("Zero hollow praise across all 5 turns",
              total_praise == 0,
              f"total_praise={total_praise} | violations={violations}"),
        check("No numbered/bulleted lists in any turn",
              not total_lists,
              f"lists found | violations={[v for v in violations if 'list' in v]}"),
        check("No markdown bold or headers in any turn",
              not total_markdown,
              f"markdown found | violations={[v for v in violations if 'markdown' in v]}"),
        check("Every turn ends with question or task",
              all_end_well,
              f"per_turn={[ends_with_question_or_task(r) for r in all_replies]}"),
        check("Natural connectors appear (tutor sounds human)",
              connectors >= 1,
              f"connector_count={connectors}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    full_transcript = "\n\n".join(f"[T{i+1}] Student: {turns[i]}\nTutor: {all_replies[i]}" for i in range(len(turns)))
    return ScenarioResult("S8: Format Compliance — 5 Turns, No Lists, No Hollow Praise", passed, checks,
                          tutor_response=full_transcript,
                          notes="5-turn grammar lesson. All turns must pass format checks.")


# ══════════════════════════════════════════════════════════════════════════════
# TOKEN USAGE REPORT
# ══════════════════════════════════════════════════════════════════════════════

def print_token_report():
    if not GLOBAL_TOKEN_LOG:
        return

    print(f"\n{BOLD}{'═'*72}{RESET}")
    print(f"{BOLD}{MAGENTA}TOKEN USAGE REPORT — v4 ({TUTOR_MODEL} tutor / {ANALYST_MODEL} analyst){RESET}")
    print(f"{'─'*72}")

    total_prompt     = sum(t["prompt_tokens"]     for t in GLOBAL_TOKEN_LOG)
    total_completion = sum(t["completion_tokens"] for t in GLOBAL_TOKEN_LOG)
    total_all        = sum(t["total_tokens"]      for t in GLOBAL_TOKEN_LOG)
    num_calls        = len(GLOBAL_TOKEN_LOG)

    tutor_calls   = [t for t in GLOBAL_TOKEN_LOG if "analyst" not in t["label"]]
    analyst_calls = [t for t in GLOBAL_TOKEN_LOG if "analyst" in t["label"]]

    print(f"  {'Call':<35} {'Model':<18} {'Prompt':>7} {'Compl':>7} {'Total':>7}")
    print(f"  {'─'*68}")
    for t in GLOBAL_TOKEN_LOG:
        print(f"  {t['label']:<35} {t.get('model','?'):<18} {t['prompt_tokens']:>7} {t['completion_tokens']:>7} {t['total_tokens']:>7}")
    print(f"  {'─'*68}")
    print(f"  {'TOTAL (' + str(num_calls) + ' calls)':<35} {'':18} {total_prompt:>7} {total_completion:>7} {total_all:>7}")

    if total_all > 0:
        tutor_in    = sum(t["prompt_tokens"]     for t in tutor_calls)
        tutor_out   = sum(t["completion_tokens"] for t in tutor_calls)
        analyst_in  = sum(t["prompt_tokens"]     for t in analyst_calls)
        analyst_out = sum(t["completion_tokens"] for t in analyst_calls)
        cost = ((tutor_in   / 1_000_000) * 2.00
              + (tutor_out  / 1_000_000) * 8.00
              + (analyst_in / 1_000_000) * 0.15
              + (analyst_out / 1_000_000) * 0.60)
        print(f"\n  Test run cost: ${cost:.4f}")

    print(f"\n{'═'*72}\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def run_all():
    print(f"\n{BOLD}{CYAN}{'═'*72}{RESET}")
    print(f"{BOLD}{CYAN}  Chat Tutor Tests v4 — Tone & Length Focus{RESET}")
    print(f"{BOLD}{CYAN}  Tutor: {TUTOR_MODEL} | Analyst: {ANALYST_MODEL} | Audio/TTS: DISABLED{RESET}")
    print(f"{BOLD}{CYAN}{'═'*72}{RESET}")

    scenarios = [
        ("S1: No Hollow Praise",             s1_no_hollow_praise),
        ("S2: Short Answer for Simple Q",    s2_short_answer_for_simple_question),
        ("S3: Complex Topic Depth",          s3_complex_topic_depth_intermediate),
        ("S4: Beginner Brevity",             s4_beginner_brevity),
        ("S5: Advanced Depth, No Lists",     s5_advanced_depth_no_lists),
        ("S6: Frustration + Motivation",     s6_frustration_with_motivation),
        ("S7: First Session Variety",        s7_first_session_variety),
        ("S8: Format Compliance 5 Turns",    s8_format_compliance_multi_turn),
    ]

    results = []
    for label, fn in scenarios:
        print(f"\n{YELLOW}▶ Running: {label}…{RESET}")
        try:
            result = fn()
            results.append(result)
            print_scenario(result)
        except Exception as e:
            import traceback
            print(f"{RED}ERROR: {e}{RESET}")
            traceback.print_exc()
            results.append(ScenarioResult(label, False, [check("Exception", False, str(e)[:200])]))

    total  = len(results)
    passed = sum(1 for r in results if r.passed)

    print(f"\n\n{BOLD}{'═'*72}{RESET}")
    print(f"{BOLD}SUMMARY — v4 Tone & Length ({TUTOR_MODEL}){RESET}")
    print(f"{'─'*72}")
    for r in results:
        icon     = PASS if r.passed else FAIL
        ok_count = sum(1 for _, ok, _ in r.checks if ok)
        print(f"  {icon}  {r.name:<52} {ok_count}/{len(r.checks)} checks")
    print(f"\n{BOLD}Result: {passed}/{total} scenarios passed{RESET}")

    failed_checks = [(r.name, l, d) for r in results if not r.passed
                     for l, ok, d in r.checks if not ok]
    if failed_checks:
        print(f"\n{RED}Failed checks:{RESET}")
        for sname, clabel, detail in failed_checks:
            print(f"  • [{sname}] {clabel}")
            if detail:
                print(f"    {DIM}{detail[:160]}{RESET}")

    print_token_report()


if __name__ == "__main__":
    run_all()
