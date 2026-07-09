# Professor Madrid × Quarks — Partnership Proposal
### Draft Term Sheet / Letter of Intent
*Version 0.2 — For Discussion Only — Not Legally Binding*

---

## The Problem We're Solving

People don't want to learn a language. They want to *already speak* one.

The desire for a magic pill is real — and it's rational. Learning a language through traditional methods takes years of tedious study, grammar tables, and exercises that feel disconnected from actual speech. The modern learner is time-poor, easily bored, and has already tried and abandoned at least one language app.

**Duolingo proved something important**: gamification works for retention. People come back. But it proved something uncomfortable too: retention and actual learning are not the same thing. The exercises are fun, but the progress is slow and often invisible. A user can complete 300 Duolingo lessons and still not hold a basic conversation. The product keeps users engaged — it does not make them fluent.

We looked at this gap and asked a different question: *what does the science say actually works?*

### The Scientific Foundation

Professor Madrid is not built on intuition. It is built on three converging bodies of research:

**1. Ebbinghaus's Forgetting Curve and Spaced Repetition**
Hermann Ebbinghaus demonstrated in 1885 that memory decays on a predictable curve — and that strategic repetition at the right intervals can flatten that curve dramatically. The Seagull Steven engine in Professor Madrid applies this directly: repeated audio exposure to a phrase at increasing intervals embeds it in long-term memory, not short-term recall. This is the same mechanism used in elite military language training programs.

**2. Krashen's Comprehensible Input Hypothesis**
Stephen Krashen's foundational work on second language acquisition argues that language is *acquired*, not *learned* — through exposure to real, contextual input that is slightly above the learner's current level. You do not learn Spanish by studying Spanish. You acquire it by being immersed in it at the edge of your comprehension. The Chat Tutor is built around this: the AI calibrates every response to push the learner forward without overwhelming them. It teaches the way a native speaker would teach a friend — in context, not in isolation.

**3. Embodied Cognition and Contextual Memory Binding**
Research across developmental psychology and cognitive science consistently shows that words learned in context — attached to real objects, scenes, and physical experience — are retained exponentially better than words learned from lists or flashcards. This is how children acquire their first language: not by studying vocabulary, but by pointing at things. The Street View mode is a direct application of this: the learner photographs their real environment, and the AI builds a lesson from it. The word for "kettle" is now attached to *your* kettle, in *your* kitchen. That memory binding is neurologically different from a flashcard. It lasts.

### Where We Are Today

The app is fully functional and currently being tested by the creator and a small group of early users. The feedback loop is active. The product is not a prototype — it is a working, deployable application ready for its first real audience.

---

## What Professor Madrid Is

**An AI-powered iOS Spanish learning app** with three distinct but interconnected modes:

| Mode | What it does |
|---|---|
| **Chat Tutor** | Live AI conversation with a tutor personality — voice, text, photos, any topic |
| **Street View** | Point your camera at your surroundings; AI builds a vocabulary lesson from your real world |
| **Verb Game** | A slot machine draws 3 random verbs; you fill the full conjugation matrix by speaking — fast, mechanical, effective |
| **Seagull Steven** | Neuro-repetition engine: loops any phrase 1–20× with word-by-word karaoke highlighting until it's in long-term memory |

The benchmark is not Duolingo. It is a €50/hour native Spanish private tutor. Professor Madrid wins.

---

## What Has Already Been Built

This is not a concept. The following components are live, tested, and operational:

### Application Layer
- Full iOS app (Swift/SwiftUI) — production-ready, App Store submission-ready
- Two complete learning modes (Chat Tutor + Verb Game) with full session history and continuity
- Seagull Steven neuro-repetition audio engine
- Street View visual learning mode using frontier vision models

### Authentication
- **Sign in with Apple** — fully configured and tested
- **Sign in with Google** — fully configured and tested
- Session management and user persistence via Supabase

### Backend and Infrastructure
- **Supabase** (PostgreSQL-based) for database, auth, and real-time data — portable to any cloud provider's managed Postgres if preferred (Google Cloud SQL, Amazon RDS, etc.)
- All infrastructure components are cloud-agnostic and can be migrated to Quarks's preferred environment without significant architectural changes

### AI Stack
- **Google Cloud** for speech-to-text (voice input recognition, tuned for language learner pronunciation) and text-to-speech (natural-sounding Spanish audio output)
- **Frontier conversation models** (OpenAI) for the Chat Tutor, Street View, and verb game logic
- **OpenAI fallback layer** already integrated — API keys and model routing can be switched to Quarks's accounts and infrastructure with a configuration change, not a rewrite
- All AI costs are usage-based and fully trackable per user session

### Analytics
- Analytics infrastructure is already configured and live — a real-time dashboard exists today
- The stack is designed to connect to any standard mobile analytics platform: **Amplitude**, **Mixpanel**, Firebase Analytics, or any equivalent tool Quarks already uses
- Event tracking covers: session starts, mode usage, voice input attempts, conjugation accuracy, Seagull Steven activations, subscription funnel events

### Distribution Assets
- **Landing page** — live and operational
- **Custom domain** — configured
- App icon, screenshots, App Store copy — all prepared
- All of these assets transfer to Quarks as part of this agreement

---

## Strategic Context

The creator is proposing to transfer full ownership of this asset to Quarks in exchange for a long-term revenue share, with a commitment to continue developing and improving the product under Quarks's infrastructure.

This is not a license. This is a transfer of a live, working product — with all its infrastructure, analytics, distribution assets, and ongoing development — in exchange for a partnership that funds its growth.

---

## What Each Party Brings

| | Creator | Quarks |
|---|---|---|
| **Asset** | Fully functional iOS app + source code + all infrastructure + domain + landing page | App Store account + payment infrastructure |
| **Ongoing commitment** | Active development, feature roadmap, bug fixes, technical support | Operations, AI token costs, infrastructure, marketing budget, team financing |
| **Financial exposure** | Up to $1,000 symbolic seed contribution | Operational costs: AI tokens, infrastructure, support, advertising |
| **Risk** | Time, intellectual property, opportunity cost | Cash, operational overhead, distribution risk |

---

## Proposed Terms

### 1. Revenue Share

- **Creator receives**: **30% of gross revenue** received by Quarks from this app, after the App Store's standard 30% commission.
  - *Example: $100 paid by user → Apple keeps $30 → Quarks receives $70 → Creator receives $21 (30% of $70)*
- **Quarks receives**: 70% of gross revenue after Apple's cut, from which all operational costs are covered.
- Revenue share applies to: in-app purchases, subscriptions, one-time purchases, any monetization model Quarks implements for this app.
- Payments are made **monthly**, within 15 days of the end of each calendar month.
- Even at $0 revenue, Quarks provides monthly statements.

> **Rationale on the 30% rate**: This is the market-standard range (25–35%) for a creator who transfers a working, commercially viable product and commits to ongoing active development — not just a one-time handover. The creator is effectively a permanent technical co-founder without an equity stake. Hiring a senior iOS developer with AI integration experience to build this from scratch would cost $80,000–$150,000. The creator is not asking for any of that.

---

### 2. Code Ownership and IP Transfer

- **Effective upon signing**, the source code, all associated assets (icons, audio files, prompts, data models, landing page, domain), and the app itself become the property of Quarks.
- Creator transfers access to all repositories, build pipelines, API configurations, and credentials.
- Creator commits to continuing development using **Quarks's GitHub accounts and infrastructure** — meaning Quarks always holds the latest version of the code, no exceptions.
- Creator will not fork, clone, or independently publish any version of this app or a functionally equivalent application under any entity.

---

### 3. Exclusivity and Non-Compete

Both parties agree:

- **Creator**: will not build or release a functionally equivalent Spanish language learning app targeting the same audience while this agreement is active.
- **Quarks**: will not apply this codebase (in whole or significant part) to a different product, release it from an alternate account, or sublicense the code to any third party without written consent from the creator.
- The reuse prohibition covers both direct copying and derivative works that preserve the core architecture of the product (voice tutor, verb game, Seagull Steven engine, Street View mode).

> *Note: This clause relies on mutual trust and the existing professional relationship. If Quarks is ever found in breach, creator is entitled to release their own version with no further obligation under this agreement.*

---

### 4. Analytics Access

- Creator receives **read-only access** to all analytics platforms connected to this app: App Store Connect, payment analytics (RevenueCat or equivalent), and the in-app usage analytics platform.
- Quarks chooses the analytics tooling. The existing infrastructure can connect directly to Amplitude, Mixpanel, or any platform Quarks already operates.
- Creator's access must be provisioned within 30 days of launch.
- Creator must be able to see: daily/monthly active users, revenue per user, subscription conversion rates, churn rates, session counts, feature usage, and geographic distribution.

---

### 5. Team and Personnel Approval

- Any person who gains **access to the source code** (engineers, contractors, agencies) requires prior written approval from Creator.
- Approval cannot be unreasonably withheld. Creator has 5 business days to respond; silence = approval.
- For roles that do not involve code access (copywriters, designers working on marketing assets, customer support), no approval is required.
- Creator may propose team members. Quarks may propose team members. Both parties may veto. Costs for approved team members are borne by Quarks.

---

### 6. Quarks's Investment Commitment

Creator requests that Quarks commits to a **minimum operational investment** over the first 90 days to ensure the app is seriously launched, not parked:

| Category | Estimated Monthly Cost | 90-Day Commitment |
|---|---|---|
| AI token costs (Google Cloud + OpenAI APIs) | $500–$2,000 | $1,500–$6,000 |
| Infrastructure (Supabase / Cloud DB, storage) | $100–$300 | $300–$900 |
| App Store Developer Account | $99/year | $99 (one-time) |
| Marketing / Paid Acquisition (minimum) | $1,000–$3,000 | $3,000–$9,000 |
| **Total Estimated Minimum** | | **~$5,000–$16,000** |

> A commitment to launch with at least $5,000 in operational budget over 90 days signals that Quarks is treating this as a real product, not a passive asset.

---

### 7. Creator's Seed Contribution

Creator commits up to **$1,000** as a symbolic co-investment — demonstrating alignment and shared risk. This is not equity; it is a gesture of commitment. It may be used toward any agreed launch expense (creative assets, beta testing incentives, initial token costs).

---

### 8. Reporting and Governance

- **Monthly report**: Quarks provides a one-page summary — revenue, active users, operational costs, key decisions made.
- **Quarterly review**: 30-minute call to review performance, roadmap priorities, and partnership health.
- **Decision authority**:
  - Quarks decides: pricing, marketing strategy, customer support policy, team hiring (subject to code access clause above), business entity, payment processor.
  - Creator decides: technical architecture, feature prioritization (subject to consultation), code quality standards.
  - Joint decisions: major monetization model changes, pivots in target market, public-facing brand changes.

---

### 9. Term and Exit

- **Initial term**: 24 months from the date of first public release on the App Store.
- **Auto-renewal**: 12-month periods unless either party gives 90 days written notice.
- **Termination for cause**: Either party may terminate with 30 days notice if the other materially breaches the agreement and fails to cure within 15 days.
- **What happens on termination**:
  - If Quarks terminates or fails to maintain minimum operational investment: source code rights revert to Creator; Creator may republish the app freely.
  - If Creator terminates without cause: Quarks retains the code and current state of the product; Creator's revenue share ends; Creator may not release a competing app for 12 months.
- **Acquisition clause**: If Quarks is acquired, the acquiring entity inherits this agreement unchanged. If Quarks wishes to sell this app as a standalone asset, Creator receives 30% of the sale price.

---

## What This Proposal Is Not Covering Yet

The following items are intentionally left for a second conversation once the high-level structure is agreed:

- Exact pricing model (freemium vs. subscription vs. one-time purchase)
- Which markets to launch in first
- App Store metadata and localization strategy
- Specific marketing channels and budget allocation
- Service-level commitments for bug fixes and uptime

---

## Recommended Next Steps

1. **Share this document** as a discussion draft — not a legal document.
2. **Agree on the 3 core terms**: revenue split %, investment commitment floor, and the code-reuse prohibition. Everything else is detail.
3. Once aligned in principle, **engage a lawyer** to formalize a proper Collaboration Agreement or IP Transfer + Revenue Share Agreement. Budget ~$500–$1,500 for legal drafting. Split the cost 50/50.
4. **Set a go-live target date** as part of the conversation — even an aspirational one. Without a date, this stalls.

---

*This document was prepared by the Creator for discussion purposes only. It does not constitute a binding offer or legal agreement.*
