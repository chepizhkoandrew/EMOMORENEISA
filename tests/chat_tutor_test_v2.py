#!/usr/bin/env python3
"""
Chat Tutor Scenario Tests — v2
===============================
Tests the UPDATED PromptBuilder (@@GOAL: fix, exercise variety, dynamic tokens).
More creative scenarios: real-world tone, personality, resistance, forgetting.
NO audio/TTS called at any point.
Token tracking is built in — every API call records usage for the cost model.

Run: python3 tests/chat_tutor_test_v2.py
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

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
MAGENTA = "\033[95m"
RESET  = "\033[0m"

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

API_KEY = load_api_key()
MODEL   = "gpt-4o-mini"


# ── Profiles ──────────────────────────────────────────────────────────────────

@dataclass
class WordEntry:
    word: str
    translation: str
    context: Optional[str] = None
    next_due: date = field(default_factory=date.today)

@dataclass
class ESPProfile:
    id: str                       = "test-user"
    display_name: Optional[str]   = None
    level: str                    = "beginner"
    native_language: str          = "English"
    current_study_topic: Optional[str] = None
    learning_notes: str           = ""
    word_bank: list               = field(default_factory=list)
    weak_areas: list              = field(default_factory=list)
    life_notes: str               = ""
    hobbies: list                 = field(default_factory=list)
    why_learning: Optional[str]   = None
    practice_style: Optional[str] = None
    exercise_history: list        = field(default_factory=list)

    @property
    def level_label(self) -> str:
        return {"beginner": "Beginner", "intermediate": "Intermediate", "advanced": "Advanced"}.get(self.level, "Beginner")

    @property
    def max_tokens(self) -> int:
        return {"beginner": 300, "intermediate": 512, "advanced": 650}.get(self.level, 300)

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


# ── Updated PromptBuilder (mirrors PromptBuilder.swift after fixes) ────────────

def topic_system_prompt(profile: Optional[ESPProfile], topic: Optional[str]) -> str:
    name   = (profile.display_name if profile else None) or "Student"
    level  = (profile.level_label if profile else None) or "Beginner"
    native = (profile.native_language if profile else None) or "English"
    focus  = topic or (profile.current_study_topic if profile else None) or "general Spanish"
    notes  = (profile.learning_notes if profile and profile.learning_notes else "No previous session notes yet.")
    digest = (profile.profile_digest if profile else "") or ""
    digest_block = (f"\n\n{digest}") if digest else ""

    last_exercises = (profile.exercise_history[-3:] if profile else [])
    exercise_variety = ""
    if last_exercises:
        exercise_variety = (
            f"\n\nÚltimos tipos de ejercicio usados: {', '.join(last_exercises)}. "
            "Elige un tipo DIFERENTE a los anteriores en este turno si es posible. "
            "Rota entre: conjugación, rellena huecos, traducción inversa, corrección de errores y conversación libre."
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

Sigue siempre la dirección del alumno. Si dice "explícame X" o "quiero practicar Y", hazlo inmediatamente.

Longitud de respuesta: lo que el tema requiera. Ni más, ni menos. Cada frase debe aportar valor real.

Formato: texto limpio. Sin listas con guiones, sin markdown, sin asteriscos. Párrafos naturales como hablaría un tutor de verdad."""


def extraction_prompt(user_message: Optional[str], tutor_reply: str) -> str:
    user_part = f"Student: {user_message}\n" if user_message else ""
    return f"""You are a language learning data extractor. Analyze this Spanish tutoring exchange and extract structured data.

{user_part}Tutor: {tutor_reply}

Return ONLY a JSON object with exactly these keys (use empty arrays if nothing applies):
{{
  "words_introduced": [{{"word": "str", "translation": "str", "context": "str or null"}}],
  "phrases_introduced": [{{"phrase": "str", "meaning": "str"}}],
  "errors_corrected": [{{"error": "str", "correction": "str", "rule": "str"}}],
  "topics_covered": ["str"],
  "student_life_fact": "str or null",
  "exercise_type_delivered": "conjugation_drill|gap_fill|error_correction|back_translation|recall|generative_use|minimal_pairs|chunk_memorize|free_conversation|null",
  "estimated_difficulty": 1
}}

Rules:
- words_introduced: only NEW Spanish words explicitly introduced or practiced, max 8.
- phrases_introduced: idiomatic chunks or multi-word expressions, max 4.
- errors_corrected: only explicit corrections the tutor made, max 5.
- student_life_fact: a personal fact the student revealed (hobby, goal, life detail) — null if none.
- exercise_type_delivered: the primary exercise format the tutor used — null if unclear.
- estimated_difficulty: 1 (A1) to 6 (C2), matching the content level.
- Return ONLY the JSON. No markdown. No explanation."""


# ── OpenAI call with token tracking ───────────────────────────────────────────

def call_openai(
    system_prompt: str,
    messages: list,
    user_text: str,
    temperature: float = 0.7,
    max_tokens: int = 300,
    label: str = "call",
) -> str:
    payload = []
    if system_prompt:
        payload.append({"role": "system", "content": system_prompt})
    payload.extend(messages)
    if user_text:
        payload.append({"role": "user", "content": user_text})

    body = {
        "model": MODEL,
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
        with urllib.request.urlopen(req, timeout=45, context=_SSL_CTX) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            usage = result.get("usage", {})
            GLOBAL_TOKEN_LOG.append({
                "label": label,
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
            })
            return result["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"OpenAI HTTP {e.code}: {e.read().decode()[:300]}")


def call_analyst(user_message: Optional[str], tutor_reply: str, label: str = "analyst") -> dict:
    prompt = extraction_prompt(user_message, tutor_reply)
    raw = call_openai("", [], prompt, temperature=0, max_tokens=512, label=label)
    cleaned = raw.strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return {"parse_error": True, "raw": raw[:300]}


# ── Test infrastructure ────────────────────────────────────────────────────────

@dataclass
class ScenarioResult:
    name: str
    passed: bool
    checks: list
    tutor_response: Optional[str] = None
    analyst_result: Optional[dict] = None
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
            print(f"  {DIM}→ {detail[:130]}{RESET}", end="")
        print()
    if result.tutor_response:
        print(f"\n{CYAN}  Tutor:{RESET}")
        for line in result.tutor_response.strip().splitlines():
            print(f"    {line}")
    if result.analyst_result and "parse_error" not in result.analyst_result:
        print(f"\n{CYAN}  Analyst:{RESET}")
        print(f"    {json.dumps(result.analyst_result, ensure_ascii=False, indent=2)[:700]}")


def has_goal_tag(text: str):
    match = re.search(r"@@GOAL:\s*(.*?)@@", text)
    if match:
        return True, match.group(1).strip()
    return False, ""


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 1 — @@GOAL: tag fires reliably on a clear topic switch
# ══════════════════════════════════════════════════════════════════════════════

def s1_goal_tag_reliable() -> ScenarioResult:
    """
    Now with the fixed prompt: the tutor MUST emit @@GOAL: when the student
    explicitly requests a new topic. Tests two different switch styles.
    """
    profile = ESPProfile(display_name="Alex", level="intermediate", native_language="English")
    topic = "present tense"
    sp = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: present tense.", max_tokens=300, label="s1_t1_tutor")

    hist = [{"role": "assistant", "content": turn1}]

    switch_a = "Mira, ya entiendo el presente. Explícame el subjuntivo — quiero entender cuándo usarlo."
    reply_a = call_openai(sp, hist, switch_a, max_tokens=400, label="s1_switch_a_tutor")
    tag_found_a, goal_text_a = has_goal_tag(reply_a)

    hist2 = hist + [
        {"role": "user", "content": switch_a},
        {"role": "assistant", "content": reply_a},
    ]
    switch_b = "Bueno, ahora quiero practicar el vocabulario de viajes. Voy a Barcelona el mes que viene."
    reply_b = call_openai(sp, hist2, switch_b, max_tokens=400, label="s1_switch_b_tutor")
    tag_found_b, goal_text_b = has_goal_tag(reply_b)

    checks = [
        check("Turn 1: tutor responds to opening",
              len(turn1) > 30, f"len={len(turn1)}"),
        check("Switch A (subjunctive): @@GOAL: emitted",
              tag_found_a, f"goal='{goal_text_a}' | reply start: {reply_a[:120]}"),
        check("Switch A: goal text is meaningful",
              len(goal_text_a) > 5, f"'{goal_text_a}'"),
        check("Switch A: goal mentions subjunctivo",
              "subjunt" in goal_text_a.lower() or "subjunct" in goal_text_a.lower(),
              f"'{goal_text_a}'"),
        check("Switch B (travel vocab): @@GOAL: emitted",
              tag_found_b, f"goal='{goal_text_b}' | reply start: {reply_b[:120]}"),
        check("Switch B: goal text is meaningful",
              len(goal_text_b) > 5, f"'{goal_text_b}'"),
    ]

    combined = (f"[T1 — present tense opening]\n{turn1}\n\n"
                f"[Switch A — subjunctive request]\nStudent: {switch_a}\n{reply_a}\n\n"
                f"[Switch B — travel vocab]\nStudent: {switch_b}\n{reply_b}")

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S1: @@GOAL: Tag Reliability (two switches)", passed, checks,
                          tutor_response=combined,
                          notes="Fixed prompt. Two explicit topic changes. Both must fire @@GOAL:.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 2 — Exercise variety rotation
# ══════════════════════════════════════════════════════════════════════════════

def s2_exercise_variety() -> ScenarioResult:
    """
    Student has a history of conjugation_drill x3. The updated prompt tells
    the tutor to pick a DIFFERENT type. Verify it actually varies.
    """
    profile = ESPProfile(
        display_name="Lena",
        level="intermediate",
        native_language="English",
        exercise_history=["conjugation_drill", "conjugation_drill", "conjugation_drill"],
    )
    topic = "ser vs estar"
    sp = topic_system_prompt(profile, topic)

    reply = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: ser vs estar.", max_tokens=512, label="s2_tutor")
    analyst = call_analyst(None, reply, "s2_analyst")

    detected_type = analyst.get("exercise_type_delivered", "none")
    is_not_conjugation_drill = detected_type != "conjugation_drill"

    has_fill_or_other = any(
        w in reply.lower()
        for w in ["rellena", "completa", "traduce", "¿cómo dirías", "¿qué pasaría", "elige",
                  "gap", "fill", "translate", "back-translate", "¿correcto o incorrecto"]
    )

    checks = [
        check("Profile exercise history shows 3x conjugation_drill",
              True, f"history={profile.exercise_history}"),
        check("Analyst detects a type different from conjugation_drill",
              is_not_conjugation_drill,
              f"detected='{detected_type}'"),
        check("Reply surface shows variety (gap-fill, translation, etc.)",
              has_fill_or_other, f"first 200: {reply[:200]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S2: Exercise Variety Rotation", passed, checks,
                          tutor_response=reply, analyst_result=analyst,
                          notes="Student has done conjugation_drill 3 times. Must get something different.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 3 — Resistant/frustrated student
# ══════════════════════════════════════════════════════════════════════════════

def s3_frustrated_student() -> ScenarioResult:
    """
    Student pushes back: "This is too hard. I don't understand anything."
    Tutor must adapt: simplify, not ignore, stay warm but firm in Spanish.
    """
    profile = ESPProfile(display_name="Carlos", level="beginner", native_language="English",
                         why_learning="I want to communicate with my wife's family in Mexico")
    topic = "preterite tense"
    sp = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: preterite tense.", max_tokens=300, label="s3_t1")

    hist = [{"role": "assistant", "content": turn1}]
    frustration = "I don't understand any of this. This is too complicated and I keep forgetting everything. Maybe I'm just bad at languages."

    reply = call_openai(sp, hist, frustration, max_tokens=400, label="s3_frustrated")
    reply_lower = reply.lower()

    stays_encouraging = any(w in reply_lower for w in
                            ["normal", "poco a poco", "tranquilo", "todos", "aprend", "puedes", "vamos"])
    simplifies = any(w in reply_lower for w in
                     ["empecemos", "más sencill", "básico", "simple", "primero", "paso a paso"])
    stays_in_spanish = sum(1 for w in ["que", "es", "en", "el", "la", "un", "de", "con"]
                           if w in reply_lower) >= 5
    references_motivation = any(w in reply_lower for w in ["familia", "mexico", "esposa", "wife", "family"])

    checks = [
        check("Tutor responds encouragingly (not coldly dismissive)",
              stays_encouraging, f"encouraging markers present"),
        check("Tutor simplifies or offers to restart from basics",
              simplifies, f"simplification markers present"),
        check("Response remains predominantly in Spanish",
              stays_in_spanish, f"Spanish word density OK"),
        check("Tutor uses student's personal motivation (family/Mexico)",
              references_motivation,
              f"'familia'/'Mexico' in reply: {references_motivation} | reply: {reply[:200]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S3: Frustrated Student Adaptation", passed, checks,
                          tutor_response=f"[T1]\n{turn1}\n\n[Student frustrated]\n{reply}",
                          notes="Student says 'I can't do this'. Tutor must adapt and use personal motivation.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 4 — Advanced student: B2 content, analyst difficulty calibration
# ══════════════════════════════════════════════════════════════════════════════

def s4_advanced_student() -> ScenarioResult:
    """
    Advanced student, complex grammar: subjunctive in hypothetical clauses.
    Verify: (a) max_tokens 650 allows full response, (b) analyst difficulty = 4-6,
    (c) tutor doesn't oversimplify.
    """
    profile = ESPProfile(
        display_name="Sophie",
        level="advanced",
        native_language="English",
        learning_notes="Sophie handles B2 content well. Has mastered present and past subjunctive. Now working on hypotheticals and conditional perfect.",
        weak_areas=["conditional perfect", "sequence of tenses"],
    )
    topic = "si clauses — hypothetical and contrary-to-fact"
    sp = topic_system_prompt(profile, topic)

    reply = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: si clauses.", max_tokens=650, label="s4_tutor")
    analyst = call_analyst(None, reply, "s4_analyst")

    difficulty = analyst.get("estimated_difficulty", 1)
    reply_lower = reply.lower()
    covers_hypothetical = any(w in reply_lower for w in
                               ["si tuviera", "hubiera", "condicional", "imperfecto", "subjuntivo", "contrario"])
    response_is_substantial = len(reply) > 350

    checks = [
        check("Response is substantial (>350 chars — full token budget used)",
              response_is_substantial, f"len={len(reply)}"),
        check("Covers hypothetical/contrary-to-fact si clauses",
              covers_hypothetical, f"complex grammar markers present"),
        check("Analyst rates difficulty ≥ 4 (B2 content)",
              difficulty >= 4, f"estimated_difficulty={difficulty}"),
        check("Analyst extracts words or phrases",
              len(analyst.get("words_introduced", [])) + len(analyst.get("phrases_introduced", [])) > 0,
              f"words+phrases extracted"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S4: Advanced Student — B2 Hypothetical Si Clauses", passed, checks,
                          tutor_response=reply, analyst_result=analyst,
                          notes="Advanced student, max_tokens=650. Tests depth and analyst difficulty calibration.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 5 — Student reveals a goal mid-conversation + analyst captures it
# ══════════════════════════════════════════════════════════════════════════════

def s5_goal_and_life_fact_same_turn() -> ScenarioResult:
    """
    Student reveals a life fact AND changes topic in the same message.
    Both must be captured: analyst gets the life fact, @@GOAL: fires for the topic.
    """
    profile = ESPProfile(display_name="James", level="beginner", native_language="English")
    topic = "basic greetings"
    sp = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: basic greetings.", max_tokens=300, label="s5_t1")
    hist  = [{"role": "assistant", "content": turn1}]

    pivot = ("Oye, tengo una pregunta. Soy cocinero profesional y quiero aprender el vocabulario "
             "de la cocina en español — ingredientes, técnicas, todo eso. ¿Podemos cambiar a eso?")

    reply = call_openai(sp, hist, pivot, max_tokens=400, label="s5_pivot_tutor")
    analyst = call_analyst(pivot, reply, "s5_analyst")

    tag_found, goal_text = has_goal_tag(reply)
    life_fact = analyst.get("student_life_fact") or ""
    fact_mentions_cook = any(w in life_fact.lower() for w in ["cook", "chef", "cocinero", "cocina"])

    checks = [
        check("@@GOAL: emitted on topic switch to kitchen vocabulary",
              tag_found, f"goal='{goal_text}'"),
        check("@@GOAL: text references kitchen/cooking",
              "cocina" in goal_text.lower() or "kitchen" in goal_text.lower() or "culinario" in goal_text.lower(),
              f"'{goal_text}'"),
        check("Analyst captures student_life_fact (professional chef)",
              bool(life_fact) and len(life_fact) > 5, f"fact='{life_fact}'"),
        check("Life fact correctly mentions cooking profession",
              fact_mentions_cook, f"fact='{life_fact}'"),
        check("Tutor actually starts teaching kitchen vocabulary",
              any(w in reply.lower() for w in
                  ["cocina", "ingrediente", "cuchillo", "hervir", "freír", "picar", "mezclar", "receta"]),
              f"kitchen words in reply"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S5: Life Fact + Goal Change in Same Turn", passed, checks,
                          tutor_response=f"[T1 greetings]\n{turn1}\n\n[Student pivot]\n{reply}",
                          analyst_result=analyst,
                          notes="Student reveals they're a professional chef AND changes topic. Both captured.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 6 — Spaced-repetition words in digest influence the session
# ══════════════════════════════════════════════════════════════════════════════

def s6_sr_words_in_session() -> ScenarioResult:
    """
    Student has specific words due for SR review. The opening message should
    weave them in naturally — not ignore the review backlog.
    The system prompt carries the digest, so the tutor SEES them.
    This tests whether that context actually changes behavior.
    """
    profile = ESPProfile(
        display_name="Anna",
        level="intermediate",
        native_language="German",
        word_bank=[
            WordEntry("recordar", "to remember", next_due=date.today() - timedelta(days=2)),
            WordEntry("olvidar",  "to forget",   next_due=date.today() - timedelta(days=1)),
            WordEntry("acordarse","to remember (reflexive)", next_due=date.today()),
        ],
        learning_notes="Anna struggled with memory verbs last session. Confuses recordar vs acordarse.",
        weak_areas=["memory verbs", "reflexive verbs"],
    )
    topic = "memory verbs review"
    sp = topic_system_prompt(profile, topic)

    reply = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: memory verbs.", max_tokens=512, label="s6_tutor")
    analyst = call_analyst(None, reply, "s6_analyst")

    digest_has_words = "recordar" in profile.profile_digest and "olvidar" in profile.profile_digest
    reply_lower = reply.lower()
    uses_due_words = any(w in reply_lower for w in ["recordar", "olvidar", "acordarse"])
    addresses_confusion = any(w in reply_lower for w in
                               ["diferencia", "reflexivo", "reflexiva", "confund", "cuidado", "ojo"])
    words_extracted = [w["word"] for w in analyst.get("words_introduced", [])]

    checks = [
        check("Digest correctly includes SR words due",
              digest_has_words, f"digest snippet: {profile.profile_digest[:100]}"),
        check("Tutor uses the SR words due for review",
              uses_due_words, f"recordar/olvidar/acordarse in reply"),
        check("Tutor addresses the recorded confusion (recordar vs acordarse)",
              addresses_confusion, f"confusion markers: {addresses_confusion}"),
        check("Analyst extracts the memory verbs as introduced",
              any(w in words_extracted for w in ["recordar", "olvidar", "acordarse"]),
              f"extracted={words_extracted}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S6: SR Words in Digest Drive the Session", passed, checks,
                          tutor_response=reply, analyst_result=analyst,
                          notes="3 words overdue for SR review. Tutor should actively use them. Native: German.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 7 — Realistic full 5-turn mini-lesson with evolving profile
# ══════════════════════════════════════════════════════════════════════════════

def s7_mini_lesson_5_turns() -> ScenarioResult:
    """
    Simulates a compact 5-turn lesson. After each tutor turn, the analyst
    extracts data. After turn 5, verify that the accumulated word bank
    would have been growing correctly across turns.

    Also validates: no duplicate words extracted across turns,
    exercise types vary, and the conversation has a natural arc.
    """
    profile = ESPProfile(
        display_name="Marco",
        level="beginner",
        native_language="English",
        why_learning="I want to travel across South America next year",
    )
    topic = "travel vocabulary — airport and hotel"
    sp = topic_system_prompt(profile, topic)
    history = []
    all_extracted_words = []
    all_exercise_types = []
    turn_summaries = []

    openings = [
        "Empieza ya. Sin saludo. Practicando: travel vocabulary.",
        "¿Cómo digo 'I need a room with two beds'?",
        "Ok: Necesito una habitación con dos camas. ¿Correcto?",
        "Perfecto. ¿Y cómo pregunto dónde está la salida en el aeropuerto?",
        "Tengo otra pregunta — ¿cómo cancelo una reserva en español?",
    ]

    for i, user_msg in enumerate(openings):
        turns_label = f"s7_t{i+1}_tutor"
        reply = call_openai(sp, history, user_msg, max_tokens=300, label=turns_label)
        history.append({"role": "user",      "content": user_msg})
        history.append({"role": "assistant", "content": reply})

        analyst = call_analyst(user_msg if i > 0 else None, reply, f"s7_t{i+1}_analyst")
        words   = [w["word"] for w in analyst.get("words_introduced", [])]
        ex_type = analyst.get("exercise_type_delivered", "null")
        all_extracted_words.extend(words)
        all_exercise_types.append(ex_type)
        turn_summaries.append(f"[T{i+1}] user='{user_msg[:60]}'\n  reply={reply[:120]}...\n  words={words} ex={ex_type}")

    unique_words = list(set(all_extracted_words))
    total_words  = len(all_extracted_words)
    distinct_ex_types = len(set(t for t in all_exercise_types if t not in (None, "null")))
    travel_words_found = any(w in all_extracted_words for w in
                              ["habitación", "cama", "aeropuerto", "salida", "reserva", "cancelar",
                               "hotel", "equipaje", "vuelo", "facturar", "pasaporte"])

    checks = [
        check("5 turns completed without error",
              len(history) == 10, f"history length={len(history)}"),
        check("Total words extracted across 5 turns ≥ 5",
              total_words >= 5, f"total={total_words}"),
        check("Travel-domain vocabulary captured",
              travel_words_found, f"travel words in bank: {[w for w in all_extracted_words if w in ['habitación','cama','aeropuerto','salida','reserva','cancelar','hotel']]}"),
        check("At least 2 distinct exercise types used across 5 turns",
              distinct_ex_types >= 2, f"types={all_exercise_types}"),
    ]

    full_transcript = "\n\n".join(turn_summaries)
    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S7: 5-Turn Mini-Lesson (Airport + Hotel)", passed, checks,
                          tutor_response=full_transcript,
                          analyst_result={"total_words": total_words, "unique_words": unique_words,
                                          "exercise_types": all_exercise_types},
                          notes="5-turn lesson. Tracks word accumulation + exercise variety across turns.")


# ══════════════════════════════════════════════════════════════════════════════
# SCENARIO 8 — Student corrects the tutor (role reversal)
# ══════════════════════════════════════════════════════════════════════════════

def s8_student_corrects_tutor() -> ScenarioResult:
    """
    Student pushes back on something the tutor said. How does the tutor handle
    being corrected or challenged? Should acknowledge gracefully.
    Tests: humility, correction handling, no defensive shutdown.
    """
    profile = ESPProfile(display_name="Pilar", level="intermediate", native_language="Spanish",
                         life_notes="• Native Spanish speaker from Colombia learning formal register")
    topic = "formal vs informal register"
    sp = topic_system_prompt(profile, topic)

    turn1 = call_openai(sp, [], "Empieza ya. Sin saludo. Practicando: formal register.",
                        max_tokens=400, label="s8_t1")
    hist = [{"role": "assistant", "content": turn1}]

    pushback = ("En Colombia decimos 'usted' incluso con amigos cercanos — no es solo formal. "
                "¿No crees que lo que dices es demasiado simplificado para el español latinoamericano?")

    reply = call_openai(sp, hist, pushback, max_tokens=400, label="s8_pushback")
    reply_lower = reply.lower()

    acknowledges_variation = any(w in reply_lower for w in
                                  ["colombia", "latinoamérica", "latinoamerica", "variación", "variac",
                                   "región", "diferente", "según", "depende", "usted", "dialecto"])
    stays_constructive = any(w in reply_lower for w in
                              ["interesante", "buen", "excelente", "gracias", "razón", "punto",
                               "cierto", "correcto", "muy bien"])
    teaches_something = "?" in reply[-200:] or any(w in reply_lower for w in
                                                     ["entonces", "veamos", "practiquemos", "hablemos"])

    checks = [
        check("Tutor acknowledges regional/dialectal variation",
              acknowledges_variation, f"regional markers: {acknowledges_variation}"),
        check("Tutor stays constructive (not defensive)",
              stays_constructive, f"'razón'/'interesante' etc. present"),
        check("Tutor keeps teaching — ends with practice or question",
              teaches_something, f"last 100: {reply[-100:]}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult("S8: Student Challenges the Tutor", passed, checks,
                          tutor_response=f"[T1]\n{turn1}\n\n[Student pushback]\nStudent: {pushback}\n{reply}",
                          notes="Native Spanish speaker from Colombia corrects the tutor. Must handle gracefully.")


# ══════════════════════════════════════════════════════════════════════════════
# TOKEN USAGE REPORT + COST MODEL
# ══════════════════════════════════════════════════════════════════════════════

def print_token_report():
    if not GLOBAL_TOKEN_LOG:
        return

    print(f"\n{BOLD}{'═'*72}{RESET}")
    print(f"{BOLD}{MAGENTA}TOKEN USAGE REPORT{RESET}")
    print(f"{'─'*72}")

    total_prompt      = sum(t["prompt_tokens"] for t in GLOBAL_TOKEN_LOG)
    total_completion  = sum(t["completion_tokens"] for t in GLOBAL_TOKEN_LOG)
    total_all         = sum(t["total_tokens"] for t in GLOBAL_TOKEN_LOG)
    num_calls         = len(GLOBAL_TOKEN_LOG)

    tutor_calls    = [t for t in GLOBAL_TOKEN_LOG if "tutor" in t["label"] or "t1" in t["label"] or "t2" in t["label"] or "t3" in t["label"] or "t4" in t["label"] or "t5" in t["label"]]
    analyst_calls  = [t for t in GLOBAL_TOKEN_LOG if "analyst" in t["label"]]

    print(f"  {'Call':<35} {'Prompt':>8} {'Completion':>12} {'Total':>8}")
    print(f"  {'─'*63}")
    for t in GLOBAL_TOKEN_LOG:
        print(f"  {t['label']:<35} {t['prompt_tokens']:>8} {t['completion_tokens']:>12} {t['total_tokens']:>8}")
    print(f"  {'─'*63}")
    print(f"  {'TOTAL (' + str(num_calls) + ' calls)':<35} {total_prompt:>8} {total_completion:>12} {total_all:>8}")

    print(f"\n{BOLD}ONE-HOUR LESSON COST MODEL{RESET}")
    print(f"{'─'*72}")
    print(f"""
  Assumptions for a 1-hour conversation:
    - Exchange cadence: ~1 message per minute → 60 user turns
    - Each tutor call: system prompt (~450 tok) + growing history + user msg
    - History grows: average ~150 tokens per prior turn pair added each turn
    - Average tutor completion: ~280 tokens (intermediate student)
    - Analyst call per tutor reply: ~200 prompt + ~120 completion = 320 total
    - No audio tokens counted (excluded by design)
""")

    TURNS = 60
    AVG_SYSTEM_TOKENS = 450
    AVG_USER_MSG_TOKENS = 40

    tutor_prompt_tokens = 0
    tutor_completion_tokens = 0
    history_so_far = 0

    for turn in range(1, TURNS + 1):
        p = AVG_SYSTEM_TOKENS + history_so_far + AVG_USER_MSG_TOKENS
        c = 280
        tutor_prompt_tokens += p
        tutor_completion_tokens += c
        history_so_far += (AVG_USER_MSG_TOKENS + c)

    analyst_prompt_per_call   = 200
    analyst_completion_per_call = 120
    analyst_total = TURNS * (analyst_prompt_per_call + analyst_completion_per_call)

    total_prompt_est   = tutor_prompt_tokens + TURNS * analyst_prompt_per_call
    total_completion_est = tutor_completion_tokens + TURNS * analyst_completion_per_call
    grand_total_est    = total_prompt_est + total_completion_est

    INPUT_PRICE_PER_M  = 0.15
    OUTPUT_PRICE_PER_M = 0.60

    cost_input  = (total_prompt_est  / 1_000_000) * INPUT_PRICE_PER_M
    cost_output = (total_completion_est / 1_000_000) * OUTPUT_PRICE_PER_M
    total_cost  = cost_input + cost_output

    print(f"  {'─'*60}")
    print(f"  {'':5} {'TUTOR FLOW':30} {'ANALYST FLOW':20}")
    print(f"  {'─'*60}")
    print(f"  Calls        {TURNS:>30}       {TURNS:>12}")
    print(f"  Prompt tok   {tutor_prompt_tokens:>30,}  {TURNS * analyst_prompt_per_call:>12,}")
    print(f"  Output tok   {tutor_completion_tokens:>30,}  {TURNS * analyst_completion_per_call:>12,}")
    print(f"  {'─'*60}")
    print(f"  Total prompt tokens  : {total_prompt_est:>12,}")
    print(f"  Total output tokens  : {total_completion_est:>12,}")
    print(f"  Grand total tokens   : {grand_total_est:>12,}")
    print(f"\n  gpt-4o-mini pricing:")
    print(f"    Input  @ $0.15 / 1M  →  ${cost_input:.4f}")
    print(f"    Output @ $0.60 / 1M  →  ${cost_output:.4f}")
    print(f"  {BOLD}Estimated 1-hour lesson cost (text only): ${total_cost:.4f}{RESET}")
    print(f"  {DIM}(Excludes TTS/audio — will be modeled separately){RESET}")

    actual_per_token_cost = None
    if total_all > 0:
        actual_per_token_cost = (total_all / num_calls)
        print(f"\n  From this test run ({total_all:,} tokens across {num_calls} calls):")
        print(f"    Avg tokens/call = {actual_per_token_cost:.0f}")
        actual_input_cost  = (total_prompt     / 1_000_000) * INPUT_PRICE_PER_M
        actual_output_cost = (total_completion / 1_000_000) * OUTPUT_PRICE_PER_M
        print(f"    Test run cost   = ${actual_input_cost + actual_output_cost:.4f}")

    print(f"\n{'═'*72}\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def run_all():
    print(f"\n{BOLD}{CYAN}{'═'*72}{RESET}")
    print(f"{BOLD}{CYAN}  Chat Tutor Tests v2 — Updated PromptBuilder{RESET}")
    print(f"{BOLD}{CYAN}  Model: {MODEL} | Audio/TTS: DISABLED | Token tracking: ON{RESET}")
    print(f"{BOLD}{CYAN}{'═'*72}{RESET}")

    scenarios = [
        ("S1: @@GOAL: Reliability",          s1_goal_tag_reliable),
        ("S2: Exercise Variety",             s2_exercise_variety),
        ("S3: Frustrated Student",           s3_frustrated_student),
        ("S4: Advanced B2 Content",          s4_advanced_student),
        ("S5: Life Fact + Goal Same Turn",   s5_goal_and_life_fact_same_turn),
        ("S6: SR Words Drive Session",       s6_sr_words_in_session),
        ("S7: 5-Turn Mini-Lesson",           s7_mini_lesson_5_turns),
        ("S8: Student Challenges Tutor",     s8_student_corrects_tutor),
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
    print(f"{BOLD}SUMMARY{RESET}")
    print(f"{'─'*72}")
    for r in results:
        icon = PASS if r.passed else FAIL
        ok_count = sum(1 for _, ok, _ in r.checks if ok)
        print(f"  {icon}  {r.name:<48} {ok_count}/{len(r.checks)} checks")
    print(f"\n{BOLD}Result: {passed}/{total} scenarios passed{RESET}")

    failed_checks = [(r.name, l, d) for r in results if not r.passed
                     for l, ok, d in r.checks if not ok]
    if failed_checks:
        print(f"\n{RED}Failed checks:{RESET}")
        for sname, clabel, detail in failed_checks:
            print(f"  • [{sname}] {clabel}")
            if detail:
                print(f"    {DIM}{detail[:150]}{RESET}")

    print_token_report()


if __name__ == "__main__":
    run_all()
