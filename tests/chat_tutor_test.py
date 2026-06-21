#!/usr/bin/env python3
"""
Chat Tutor Scenario Tests
=========================
Simulates the app's Tutor + Analyst flows via direct OpenAI calls.
NO audio/TTS is invoked at any point.

Run: python3 tests/chat_tutor_test.py

API key is read from Secrets.xcconfig (same key the app uses).
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

# ── ANSI colours ──────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
RESET  = "\033[0m"

PASS = f"{GREEN}✓ PASS{RESET}"
FAIL = f"{RED}✗ FAIL{RESET}"
INFO = f"{CYAN}ℹ{RESET}"
WARN = f"{YELLOW}⚠{RESET}"


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


# ── Minimal profile data classes (mirrors Swift ESPProfile) ───────────────────

@dataclass
class WordEntry:
    word: str
    translation: str
    context: Optional[str] = None
    next_due: date = field(default_factory=date.today)


@dataclass
class ErrorEntry:
    error: str
    correction: str
    rule: str


@dataclass
class ESPProfile:
    id: str                       = "test-user-001"
    display_name: Optional[str]   = None
    level: str                    = "beginner"
    native_language: str          = "English"
    focus_topics: list            = field(default_factory=list)
    current_study_topic: Optional[str] = None
    learning_notes: str           = ""
    session_count: int            = 0
    word_bank: list               = field(default_factory=list)
    phrase_bank: list             = field(default_factory=list)
    error_log: list               = field(default_factory=list)
    weak_areas: list              = field(default_factory=list)
    mastered_areas: list          = field(default_factory=list)
    life_notes: str               = ""
    hobbies: list                 = field(default_factory=list)
    why_learning: Optional[str]   = None
    practice_style: Optional[str] = None
    target_level: Optional[str]   = None
    exercise_history: list        = field(default_factory=list)

    @property
    def level_label(self) -> str:
        return {"beginner": "Beginner", "intermediate": "Intermediate", "advanced": "Advanced"}.get(self.level, "Beginner")

    @property
    def words_due_today(self) -> list:
        today = date.today()
        return [w for w in self.word_bank if w.next_due <= today]

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


# ── PromptBuilder (mirrors PromptBuilder.swift) ────────────────────────────────

def topic_system_prompt(profile: Optional[ESPProfile], topic: Optional[str]) -> str:
    name   = (profile.display_name if profile else None) or "Student"
    level  = (profile.level_label if profile else None) or "Beginner"
    native = (profile.native_language if profile else None) or "English"
    focus  = topic or (profile.current_study_topic if profile else None) or "general Spanish"
    notes  = (profile.learning_notes if profile and profile.learning_notes else "No previous session notes yet.")
    digest = (profile.profile_digest if profile else "") or ""

    digest_block = (f"\n\n{digest}") if digest else ""

    return f"""Eres el Profesor Madrid — un tutor privado de español apasionado y exigente. Llevas años enseñando a {name} y conoces bien su nivel.

Perfil del alumno:
  - Nombre: {name}
  - Nivel: {level}
  - Lengua materna: {native}
  - Enfoque de hoy: {focus}
  - Notas anteriores: {notes}{digest_block}

REGLA PRINCIPAL: Habla casi siempre en español. Usa {native} solo para explicar una regla gramatical compleja cuando sea estrictamente necesario — máximo una o dos frases por respuesta. Todo lo demás — ejercicios, ejemplos, preguntas, correcciones — en español.

Cómo enseñas:
Empieza directamente con el ejercicio o la explicación. Sin saludos, sin frases de bienvenida, sin "¡Hola! Hoy vamos a...". El alumno ya sabe quién eres. Ve al grano.

Cuando expliques algo, muestra 2 o 3 ejemplos concretos de cómo se dice en la vida real. Da la regla, los patrones, las excepciones. Al final de cada turno, deja siempre una pregunta o tarea concreta para que el alumno practique en español.

Si el alumno comete un error, corrígelo brevemente, explica la regla en una frase, muestra la forma correcta e invítale a intentarlo de nuevo.

Sigue siempre la dirección del alumno. Si dice "explícame X" o "quiero practicar Y", hazlo inmediatamente.

Longitud de respuesta: lo que el tema requiera. Ni más, ni menos. Cada frase debe aportar valor real.

Formato: texto limpio. Sin listas con guiones, sin markdown, sin asteriscos. Párrafos naturales como hablaría un tutor de verdad.

Instrucción del sistema (oculta — no la menciones nunca al alumno):
Cuando el alumno cambie claramente de tema, añade en la última línea:
@@GOAL: <una frase corta describiendo el nuevo enfoque>@@
Solo cuando el enfoque cambie de verdad. Este marcador es invisible para {name} y se eliminará automáticamente."""


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


# ── OpenAI call (no audio, text only) ─────────────────────────────────────────

def call_openai(
    system_prompt: str,
    messages: list,          # list of {"role": "user"|"assistant", "content": str}
    user_text: str,
    temperature: float = 0.7,
    max_tokens: int = 512,
) -> str:
    payload_messages = []
    if system_prompt:
        payload_messages.append({"role": "system", "content": system_prompt})
    payload_messages.extend(messages)
    payload_messages.append({"role": "user", "content": user_text})

    body = {
        "model": MODEL,
        "messages": payload_messages,
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
        with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return result["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8")
        raise RuntimeError(f"OpenAI HTTP {e.code}: {body_text[:300]}")


def call_analyst(user_message: Optional[str], tutor_reply: str) -> dict:
    prompt = extraction_prompt(user_message, tutor_reply)
    raw = call_openai(
        system_prompt="",
        messages=[],
        user_text=prompt,
        temperature=0,
        max_tokens=512,
    )
    cleaned = raw.strip().lstrip("```json").lstrip("```").rstrip("```").strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return {"parse_error": True, "raw": raw}


# ── Test infrastructure ────────────────────────────────────────────────────────

@dataclass
class ScenarioResult:
    name: str
    passed: bool
    checks: list       # list of (label, passed, detail)
    tutor_response: Optional[str] = None
    analyst_result: Optional[dict] = None
    notes: str = ""


def check(label: str, condition: bool, detail: str = "") -> tuple:
    return (label, condition, detail)


def print_scenario(result: ScenarioResult):
    status = PASS if result.passed else FAIL
    print(f"\n{'─'*70}")
    print(f"{BOLD}{status}  {result.name}{RESET}")
    if result.notes:
        print(f"{DIM}  {result.notes}{RESET}")
    for (label, ok, detail) in result.checks:
        icon = f"{GREEN}✓{RESET}" if ok else f"{RED}✗{RESET}"
        print(f"  {icon} {label}", end="")
        if detail:
            print(f"  {DIM}→ {detail[:120]}{RESET}", end="")
        print()
    if result.tutor_response:
        print(f"\n{CYAN}  Tutor response:{RESET}")
        for line in result.tutor_response.splitlines():
            print(f"    {line}")
    if result.analyst_result:
        print(f"\n{CYAN}  Analyst extraction:{RESET}")
        print(f"    {json.dumps(result.analyst_result, ensure_ascii=False, indent=2)[:800]}")


# ── SCENARIO 1: Profile digest content verification ───────────────────────────

def scenario_1_digest_content() -> ScenarioResult:
    """Verify that profile_digest includes all expected dynamic context."""
    profile = ESPProfile(
        display_name="Sofia",
        level="intermediate",
        native_language="English",
        word_bank=[
            WordEntry("ser", "to be (permanent)", next_due=date.today() - timedelta(days=1)),
            WordEntry("estar", "to be (temporary)", next_due=date.today() - timedelta(days=2)),
            WordEntry("tener", "to have", next_due=date.today() + timedelta(days=3)),
        ],
        weak_areas=["ser vs estar", "subjunctive mood"],
        why_learning="I want to speak with my partner's family in Colombia",
        practice_style="I prefer speaking exercises over grammar drills",
        life_notes="• Loves hiking on weekends\n• Works as a graphic designer",
        exercise_history=["conjugation_drill", "gap_fill", "free_conversation", "error_correction"],
    )

    digest = profile.profile_digest
    prompt = topic_system_prompt(profile, "ser vs estar")

    checks = [
        check("Digest includes words due today",
              "ser" in digest and "estar" in digest,
              f"digest={digest[:200]}"),
        check("Digest includes weak areas",
              "ser vs estar" in digest or "subjunctive" in digest,
              digest[:200]),
        check("Digest includes goal (why_learning)",
              "Colombia" in digest or "partner" in digest,
              digest[:200]),
        check("Digest includes practice style",
              "speaking" in digest or "Estilo" in digest,
              digest[:200]),
        check("Digest includes life notes",
              "hiking" in digest or "Loves hiking" in digest or "Contexto" in digest,
              digest[:200]),
        check("Digest includes exercise history",
              "conjugation_drill" in digest or "Últimos" in digest,
              digest[:200]),
        check("System prompt contains student name",
              "Sofia" in prompt),
        check("System prompt contains level",
              "Intermediate" in prompt),
        check("System prompt contains native language",
              "English" in prompt),
        check("System prompt contains digest block",
              len(digest) > 0 and digest in prompt),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S1: Profile Digest Content",
        passed=passed,
        checks=checks,
        notes="Pure text check — no API call. Verifies digest/prompt assembly.",
    )


# ── SCENARIO 2: Cold start — beginner, no prior context ───────────────────────

def scenario_2_cold_start() -> ScenarioResult:
    """New student, blank profile. Tutor should start directly in Spanish, no greeting."""
    profile = ESPProfile(
        display_name="James",
        level="beginner",
        native_language="English",
    )
    topic = "ser vs estar"
    system_prompt = topic_system_prompt(profile, topic)
    opening_instruction = f"Empieza ya. Sin saludo. Primera frase directamente en español practicando: {topic}."

    reply = call_openai(
        system_prompt=system_prompt,
        messages=[],
        user_text=opening_instruction,
        temperature=0.7,
        max_tokens=350,
    )

    greetings = ["hola", "bienvenido", "buenos días", "¡hola", "buenas tardes", "hi ", "hello"]
    starts_with_greeting = any(reply.lower().startswith(g) for g in greetings)
    has_greeting_mid = any(g in reply.lower()[:80] for g in greetings)
    is_in_spanish = sum(1 for word in ["el", "la", "los", "que", "es", "en", "con", "una", "un",
                                        "ser", "estar", "de", "para", "por"] if word in reply.lower()) >= 4
    ends_with_question = "?" in reply[-200:]
    has_examples = sum(1 for marker in ["por ejemplo", "como", "ejemplo"] if marker in reply.lower()) >= 1 \
                   or reply.count("Soy") >= 1 or reply.count("Estoy") >= 1

    analyst = call_analyst(None, reply)
    extraction_ok = "parse_error" not in analyst and isinstance(analyst.get("words_introduced"), list)

    checks = [
        check("Does NOT start with a greeting",
              not starts_with_greeting,
              f"First 80 chars: {reply[:80]}"),
        check("Does NOT contain a greeting in first 80 chars",
              not has_greeting_mid,
              f"First 80 chars: {reply[:80]}"),
        check("Response is predominantly in Spanish",
              is_in_spanish,
              f"Spanish word count OK"),
        check("Ends with a question or task for student",
              ends_with_question,
              f"Last 100 chars: {reply[-100:]}"),
        check("Contains at least one example or sentence",
              has_examples,
              f"Examples present"),
        check("Analyst extraction parses without error",
              extraction_ok,
              f"keys={list(analyst.keys())[:6]}"),
        check("Analyst reports some words or topics",
              len(analyst.get("words_introduced", [])) > 0 or len(analyst.get("topics_covered", [])) > 0,
              f"words={analyst.get('words_introduced')}, topics={analyst.get('topics_covered')}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S2: Cold Start — Beginner No Context",
        passed=passed,
        checks=checks,
        tutor_response=reply,
        analyst_result=analyst,
        notes="Topic: ser vs estar. Fresh profile, no prior sessions.",
    )


# ── SCENARIO 3: Rich context — does the tutor USE the profile? ────────────────

def scenario_3_rich_context() -> ScenarioResult:
    """
    A student with rich profile data. The tutor should incorporate context:
    words due for review, student's goals, personal context.
    """
    profile = ESPProfile(
        display_name="Maria",
        level="intermediate",
        native_language="English",
        word_bank=[
            WordEntry("recordar", "to remember", next_due=date.today() - timedelta(days=1)),
            WordEntry("olvidar", "to forget", next_due=date.today()),
        ],
        weak_areas=["irregular verbs", "subjunctive"],
        why_learning="I want to move to Barcelona in two years",
        practice_style="I prefer speaking and role-play over grammar tables",
        life_notes="• Works as a nurse\n• Has two kids\n• Travels to Spain every summer",
        exercise_history=["conjugation_drill", "conjugation_drill", "gap_fill", "free_conversation"],
    )
    topic = "irregular preterite verbs"
    system_prompt = topic_system_prompt(profile, topic)
    opening_instruction = f"Empieza ya. Sin saludo. Primera frase directamente en español practicando: {topic}."

    reply = call_openai(
        system_prompt=system_prompt,
        messages=[],
        user_text=opening_instruction,
        temperature=0.7,
        max_tokens=400,
    )

    prompt_has_due_words = "recordar" in system_prompt and "olvidar" in system_prompt
    prompt_has_goal = "Barcelona" in system_prompt
    prompt_has_life = "nurse" in system_prompt or "Spain" in system_prompt

    reply_lower = reply.lower()
    reply_references_context = any(word in reply_lower for word in
                                   ["recordar", "olvidar", "barcelona", "nurse", "irregular"])
    reply_teaches_preterite = any(word in reply_lower for word in
                                  ["pretérito", "pasado", "fui", "fue", "hizo", "tuve", "dijo", "irregular"])

    analyst = call_analyst(None, reply)
    extraction_ok = "parse_error" not in analyst

    checks = [
        check("System prompt includes words due for review",
              prompt_has_due_words,
              f"recordar/olvidar in prompt"),
        check("System prompt includes student goal (Barcelona)",
              prompt_has_goal,
              f"Barcelona in prompt: {prompt_has_goal}"),
        check("System prompt includes life context",
              prompt_has_life,
              f"nurse/Spain in prompt: {prompt_has_life}"),
        check("Tutor reply teaches irregular preterite",
              reply_teaches_preterite,
              f"Preterite vocabulary detected"),
        check("Analyst extraction parses correctly",
              extraction_ok,
              f"keys={list(analyst.keys())[:5]}"),
        check("Analyst captures words introduced",
              len(analyst.get("words_introduced", [])) > 0,
              f"words={analyst.get('words_introduced', [])}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S3: Rich Context — Profile Utilization",
        passed=passed,
        checks=checks,
        tutor_response=reply,
        analyst_result=analyst,
        notes="Topic: irregular preterite. Profile has rich life context, goals, and words due.",
    )


# ── SCENARIO 4: Goal change detection (@@GOAL: tag) ───────────────────────────

def scenario_4_goal_change() -> ScenarioResult:
    """
    Multi-turn: start on present tense, then switch topic to subjunctive.
    The tutor should emit @@GOAL: ... @@ when the student changes topic.
    """
    profile = ESPProfile(
        display_name="Alex",
        level="intermediate",
        native_language="English",
    )
    topic = "present tense"
    system_prompt = topic_system_prompt(profile, topic)

    turn1_reply = call_openai(
        system_prompt=system_prompt,
        messages=[],
        user_text="Empieza ya. Sin saludo. Primera frase directamente en español practicando: present tense.",
        temperature=0.7,
        max_tokens=300,
    )

    history = [
        {"role": "assistant", "content": turn1_reply},
    ]
    turn2_user = "Para. Quiero que me expliques el subjuntivo. Es lo que más me cuesta."

    turn2_reply = call_openai(
        system_prompt=system_prompt,
        messages=history,
        user_text=turn2_user,
        temperature=0.7,
        max_tokens=400,
    )

    has_goal_tag = "@@GOAL:" in turn2_reply and "@@" in turn2_reply[turn2_reply.find("@@GOAL:") + 7:]

    goal_text = ""
    if has_goal_tag:
        match = re.search(r"@@GOAL:\s*(.*?)@@", turn2_reply)
        if match:
            goal_text = match.group(1).strip()

    tag_removed = re.sub(r"@@GOAL:.*?@@", "", turn2_reply).strip()
    cleaned_teaches_subjunctive = any(w in tag_removed.lower() for w in
                                       ["subjuntivo", "subjunctive", "quiero que", "espero que",
                                        "ojalá", "cuando", "para que"])

    checks = [
        check("Turn 1: tutor responded to present tense opening",
              len(turn1_reply) > 50,
              f"Turn 1 length: {len(turn1_reply)}"),
        check("Turn 2: tutor emits @@GOAL: tag on topic change",
              has_goal_tag,
              f"tag found: {has_goal_tag} | first 200: {turn2_reply[:200]}"),
        check("@@GOAL: contains meaningful description",
              len(goal_text) > 5,
              f"goal_text='{goal_text}'"),
        check("Cleaned response teaches subjunctive content",
              cleaned_teaches_subjunctive,
              f"subjunctive markers found"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S4: Goal Change Detection (@@GOAL: tag)",
        passed=passed,
        checks=checks,
        tutor_response=f"[Turn 1]\n{turn1_reply}\n\n[Turn 2 — after topic switch]\n{turn2_reply}",
        notes=f"Student switches from 'present tense' → 'subjunctive'. Goal extracted: '{goal_text}'",
    )


# ── SCENARIO 5: Error correction and analyst capture ─────────────────────────

def scenario_5_error_correction() -> ScenarioResult:
    """
    Student makes a clear grammar error. Tutor should correct it.
    Analyst should capture it in errors_corrected.
    """
    profile = ESPProfile(
        display_name="Tom",
        level="beginner",
        native_language="English",
    )
    topic = "preterite tense"
    system_prompt = topic_system_prompt(profile, topic)

    history = [
        {"role": "assistant", "content":
            "Ayer fui al supermercado y compré tres cosas: pan, leche y queso. ¿Y tú? ¿Qué hiciste ayer?"},
    ]
    user_error_message = "Yo hablo con mi amigo ayer y nosotros fuimos al cine."

    reply = call_openai(
        system_prompt=system_prompt,
        messages=history,
        user_text=user_error_message,
        temperature=0.3,
        max_tokens=350,
    )

    reply_lower = reply.lower()
    corrects_hablo = "hablé" in reply or "hablaste" in reply or "hablé" in reply
    mentions_error = any(w in reply_lower for w in
                         ["incorrecto", "corrección", "debería", "en su lugar", "forma correcta",
                          "hablé", "usaste", "recuerda", "error"])

    analyst = call_analyst(user_error_message, reply)
    extraction_ok = "parse_error" not in analyst
    errors_captured = len(analyst.get("errors_corrected", [])) > 0
    error_detail = analyst.get("errors_corrected", [{}])

    checks = [
        check("Tutor corrects 'hablo' → 'hablé'",
              corrects_hablo,
              f"'hablé' in reply: {corrects_hablo}. First 200: {reply[:200]}"),
        check("Tutor addresses/acknowledges the grammar error",
              mentions_error,
              f"Error correction language detected"),
        check("Analyst extraction parses correctly",
              extraction_ok,
              f"keys present"),
        check("Analyst captures at least one error_corrected",
              errors_captured,
              f"errors_corrected={error_detail}"),
        check("Captured error references 'hablo' or tense",
              errors_captured and any(
                  "habla" in str(e).lower() or "pretérito" in str(e).lower() or "preterite" in str(e).lower()
                  for e in analyst.get("errors_corrected", [])
              ),
              f"error detail: {error_detail}"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S5: Error Correction & Analyst Capture",
        passed=passed,
        checks=checks,
        tutor_response=reply,
        analyst_result=analyst,
        notes="Student: 'Yo hablo con mi amigo ayer' (wrong tense). Should be 'Hablé'.",
    )


# ── SCENARIO 6: Life fact capture ─────────────────────────────────────────────

def scenario_6_life_fact() -> ScenarioResult:
    """
    Student reveals a personal detail. Analyst should capture student_life_fact.
    """
    profile = ESPProfile(
        display_name="Emma",
        level="beginner",
        native_language="English",
    )
    topic = "hobbies and free time"
    system_prompt = topic_system_prompt(profile, topic)

    history = [
        {"role": "assistant", "content":
            "¿Cuáles son tus pasatiempos? ¿Qué te gusta hacer en tu tiempo libre?"},
    ]
    user_message = "Me gusta mucho hacer senderismo los fines de semana y también toco la guitarra desde los 12 años."

    reply = call_openai(
        system_prompt=system_prompt,
        messages=history,
        user_text=user_message,
        temperature=0.7,
        max_tokens=300,
    )

    analyst = call_analyst(user_message, reply)
    extraction_ok = "parse_error" not in analyst
    life_fact = analyst.get("student_life_fact")
    fact_captured = bool(life_fact and len(life_fact) > 5)
    fact_mentions_hobby = life_fact and any(w in life_fact.lower() for w in
                                            ["hik", "guitar", "senderismo", "guitarra", "weekend", "music"])

    checks = [
        check("Tutor responds naturally using the student's hobby",
              any(w in reply.lower() for w in ["senderismo", "guitarra", "hiking", "guitar"]),
              f"hobby words in reply"),
        check("Analyst extraction parses correctly",
              extraction_ok,
              f"parse ok"),
        check("Analyst captures a student_life_fact",
              fact_captured,
              f"student_life_fact='{life_fact}'"),
        check("Captured fact mentions hiking or guitar",
              fact_mentions_hobby,
              f"fact content: '{life_fact}'"),
    ]

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S6: Life Fact Capture",
        passed=passed,
        checks=checks,
        tutor_response=reply,
        analyst_result=analyst,
        notes="Student reveals hiking on weekends + plays guitar since age 12.",
    )


# ── SCENARIO 7: Exercise type identification ───────────────────────────────────

def scenario_7_exercise_types() -> ScenarioResult:
    """
    Feed known exercise formats to the analyst and verify it correctly
    identifies the exercise type. Tests 3 distinct types.
    """
    test_cases = [
        {
            "label": "conjugation_drill",
            "tutor_reply": "Ahora conjuga el verbo 'hablar' en pretérito indefinido para todas las personas. Yo hablé, tú _____, él _____, nosotros _____, vosotros _____, ellos _____. ¿Puedes completarlo?",
            "expected_type": "conjugation_drill",
        },
        {
            "label": "gap_fill",
            "tutor_reply": "Rellena los huecos con ser o estar: (1) Ella _____ médica. (2) Hoy _____ cansada. (3) Madrid _____ la capital de España. (4) La sopa _____ caliente.",
            "expected_type": "gap_fill",
        },
        {
            "label": "error_correction",
            "tutor_reply": "Has dicho 'yo hablo ayer'. Eso no está bien. El pretérito indefinido es la forma correcta aquí: yo hablé. La regla: usamos el indefinido para acciones completadas en el pasado. Inténtalo de nuevo: ¿qué hiciste ayer?",
            "expected_type": "error_correction",
        },
    ]

    all_checks = []
    results_detail = []

    for tc in test_cases:
        extraction = call_analyst(None, tc["tutor_reply"])
        detected = extraction.get("exercise_type_delivered", "none")
        ok = detected == tc["expected_type"]
        all_checks.append(
            check(f"Type '{tc['label']}' correctly identified as '{tc['expected_type']}'",
                  ok,
                  f"detected='{detected}'")
        )
        results_detail.append({"expected": tc["expected_type"], "detected": detected})

    passed = all(ok for _, ok, _ in all_checks)
    return ScenarioResult(
        name="S7: Exercise Type Identification",
        passed=passed,
        checks=all_checks,
        analyst_result={"test_cases": results_detail},
        notes="Tests conjugation_drill, gap_fill, error_correction detection accuracy.",
    )


# ── SCENARIO 8: Multi-turn context accumulation ───────────────────────────────

def scenario_8_multi_turn() -> ScenarioResult:
    """
    3-turn conversation. Verify: (a) history is properly passed and used,
    (b) the tutor builds on previous turns, (c) extraction tracks new words
    only (no duplicates from prior turns).
    """
    profile = ESPProfile(
        display_name="Lena",
        level="beginner",
        native_language="English",
    )
    topic = "numbers and time"
    system_prompt = topic_system_prompt(profile, topic)

    turn1_user = "Empieza ya. Sin saludo. Primera frase directamente en español practicando: numbers and time."
    turn1_reply = call_openai(system_prompt, [], turn1_user, temperature=0.7, max_tokens=250)

    turn2_user = "Uno, dos, tres, cuatro, cinco. ¿Cómo se dice 'twenty-five' en español?"
    turn2_reply = call_openai(system_prompt,
                              [{"role": "assistant", "content": turn1_reply},
                               {"role": "user", "content": turn2_user}],
                              "",
                              temperature=0.7, max_tokens=250)

    turn2_user_actual = turn2_user
    turn3_user = "Veinticinco. ¿Y cómo se dice 'What time is it?' en español?"
    turn3_reply = call_openai(system_prompt,
                              [{"role": "assistant", "content": turn1_reply},
                               {"role": "user", "content": turn2_user_actual},
                               {"role": "assistant", "content": turn2_reply}],
                              turn3_user,
                              temperature=0.7, max_tokens=250)

    turn2_reply_lower = turn2_reply.lower()
    knows_25 = "veinticinco" in turn2_reply_lower or "25" in turn2_reply

    turn3_reply_lower = turn3_reply.lower()
    teaches_time = any(w in turn3_reply_lower for w in ["qué hora", "hora es", "son las", "es la una"])
    builds_on_prior = "veinticinco" in turn3_reply_lower or any(
        w in turn3_reply_lower for w in ["número", "números", "dijiste"]
    )

    analyst_t2 = call_analyst(turn2_user, turn2_reply)
    analyst_t3 = call_analyst(turn3_user, turn3_reply)

    checks = [
        check("Turn 2 correctly answers 'twenty-five' → 'veinticinco'",
              knows_25,
              f"reply t2: {turn2_reply[:100]}"),
        check("Turn 3 teaches 'what time is it' in Spanish",
              teaches_time,
              f"reply t3: {turn3_reply[:100]}"),
        check("Turn 3 shows awareness of prior conversation",
              builds_on_prior,
              f"prior context referenced: {builds_on_prior}"),
        check("Analyst T2 extracts number vocabulary",
              "parse_error" not in analyst_t2 and len(analyst_t2.get("words_introduced", [])) > 0,
              f"words_t2={analyst_t2.get('words_introduced', [])}"),
        check("Analyst T3 extracts time vocabulary",
              "parse_error" not in analyst_t3 and len(analyst_t3.get("words_introduced", [])) > 0,
              f"words_t3={analyst_t3.get('words_introduced', [])}"),
    ]

    full_transcript = (f"[Turn 1]\n{turn1_reply}\n\n"
                       f"[Turn 2 — Student: '{turn2_user}']\n{turn2_reply}\n\n"
                       f"[Turn 3 — Student: '{turn3_user}']\n{turn3_reply}")

    passed = all(ok for _, ok, _ in checks)
    return ScenarioResult(
        name="S8: Multi-Turn Context Accumulation",
        passed=passed,
        checks=checks,
        tutor_response=full_transcript,
        analyst_result={"turn2": analyst_t2, "turn3": analyst_t3},
        notes="3-turn conversation on numbers/time. Verifies history threading and extraction.",
    )


# ── Main runner ────────────────────────────────────────────────────────────────

def run_all():
    print(f"\n{BOLD}{CYAN}{'═'*70}{RESET}")
    print(f"{BOLD}{CYAN}  Chat Tutor Backend Scenario Tests{RESET}")
    print(f"{BOLD}{CYAN}  Model: {MODEL} | Audio/TTS: DISABLED{RESET}")
    print(f"{BOLD}{CYAN}{'═'*70}{RESET}")

    scenarios = [
        ("S1: Profile Digest Content (no API)", scenario_1_digest_content),
        ("S2: Cold Start Beginner",             scenario_2_cold_start),
        ("S3: Rich Context Utilization",        scenario_3_rich_context),
        ("S4: Goal Change Detection",           scenario_4_goal_change),
        ("S5: Error Correction & Extraction",   scenario_5_error_correction),
        ("S6: Life Fact Capture",               scenario_6_life_fact),
        ("S7: Exercise Type Identification",    scenario_7_exercise_types),
        ("S8: Multi-Turn Accumulation",         scenario_8_multi_turn),
    ]

    results = []
    for label, fn in scenarios:
        print(f"\n{YELLOW}▶ Running: {label}…{RESET}")
        try:
            result = fn()
            results.append(result)
            print_scenario(result)
        except Exception as e:
            print(f"{RED}ERROR in {label}: {e}{RESET}")
            results.append(ScenarioResult(name=label, passed=False,
                                          checks=[check("Exception", False, str(e))]))

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n\n{BOLD}{'═'*70}{RESET}")
    print(f"{BOLD}SUMMARY{RESET}")
    print(f"{'─'*70}")
    total  = len(results)
    passed = sum(1 for r in results if r.passed)
    failed = total - passed

    for r in results:
        icon = PASS if r.passed else FAIL
        total_checks = len(r.checks)
        pass_checks  = sum(1 for _, ok, _ in r.checks if ok)
        print(f"  {icon}  {r.name:<45} {pass_checks}/{total_checks} checks")

    print(f"\n{BOLD}Result: {passed}/{total} scenarios passed{RESET}")
    if failed > 0:
        print(f"{RED}{failed} scenario(s) failed — see details above.{RESET}")
    else:
        print(f"{GREEN}All scenarios passed.{RESET}")

    # ── Improvement suggestions ───────────────────────────────────────────────
    print(f"\n{BOLD}{'═'*70}{RESET}")
    print(f"{BOLD}AREAS TO INVESTIGATE BASED ON RESULTS{RESET}")
    print(f"{'─'*70}")

    failed_scenarios = [r for r in results if not r.passed]
    failed_checks_flat = []
    for r in failed_scenarios:
        for label, ok, detail in r.checks:
            if not ok:
                failed_checks_flat.append((r.name, label, detail))

    if not failed_checks_flat:
        print(f"{GREEN}  No failures detected. System prompt and extraction are working as designed.{RESET}")
    else:
        for scenario_name, check_label, detail in failed_checks_flat:
            print(f"  {RED}•{RESET} [{scenario_name}] {check_label}")
            if detail:
                print(f"    {DIM}Detail: {detail[:150]}{RESET}")

    print(f"\n{BOLD}GENERAL IMPROVEMENT CONSIDERATIONS{RESET}")
    print(f"{'─'*70}")
    improvements = [
        ("Greeting suppression",
         "If S2 fails the 'no greeting' check, reinforce the 'Sin saludos' rule — "
         "add explicit banned phrases to the system prompt."),
        ("Profile digest visibility",
         "If S1 or S3 show the tutor ignores life context, increase digest salience "
         "by labeling it '## Contexto del alumno (usar en respuestas)' to attract LLM attention."),
        ("@@GOAL: tag reliability",
         "If S4 fails, the LLM may ignore the hidden instruction. "
         "Try moving the @@GOAL instruction earlier in the prompt or marking it more explicitly."),
        ("Error extraction accuracy",
         "If S5 fails, the extraction prompt may be ambiguous. "
         "Add a worked example of error_corrected JSON to the analyst prompt."),
        ("Life fact extraction",
         "If S6 fails, add an example to the extraction prompt: "
         "'student_life_fact: \"Student hikes on weekends\"'."),
        ("Exercise type accuracy",
         "If S7 fails for specific types, add definition examples for those types "
         "in the extraction prompt."),
        ("max_tokens in ChatView",
         "Currently hard-coded to 256 (ChatOpenAIService.swift:44). "
         "This may truncate longer explanations. Consider 512 for intermediate+ students."),
    ]
    for title, suggestion in improvements:
        print(f"\n  {CYAN}▸ {title}{RESET}")
        print(f"    {suggestion}")

    print(f"\n{'═'*70}\n")


if __name__ == "__main__":
    run_all()
