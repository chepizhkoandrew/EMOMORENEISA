# Partnership with Quarks — Risks, Timeline & Strategic Preparation
*Internal analysis — not for sharing with Quarks*

---

## Before You Have the Conversation

### The Format Question: Teaser vs. Business Model

**Use a Term Sheet / LOI format. Not a full business model.**

Here's why: you don't have product economics yet. A detailed financial model with projected revenue at this stage would be fabricated, and experienced business people know it. What you need to agree on is **the structure** — who earns what, who carries the risk, who decides what. The numbers fill themselves in once the product is live.

A teaser is too thin — it signals you're not serious and haven't thought this through. A full business plan is too heavy and requires data you don't have.

A **2-page term sheet** (the draft proposal document) is exactly the right artifact. It shows you've thought carefully about the deal, it's concrete enough to react to, and it doesn't overcommit either side.

---

## Timeline: Realistic Launch Expectations

```
Week 1–2    Agreement in principle signed
Week 2–3    Code repository transferred to Quarks GitHub
            Payment infrastructure connected (RevenueCat or equivalent)
            App Store account setup / app submitted under Quarks entity
Week 3–6    Apple App Store review (typically 1–4 weeks; plan for 3)
Week 6      TestFlight beta with first 20–50 real users
Week 8      Public launch
Week 8–20   First 90-day window: analytics, iteration, marketing investment
```

**Key dependency**: App Store review. Apple can reject for policy reasons (AI features, subscription terms, content). Build in at least 2 review cycles. This is the biggest timeline risk.

---

## Risks — Ranked by Severity

### HIGH SEVERITY

**1. No formal legal agreement → everything falls apart**
The existing client relationship creates a false sense of security. Without a signed document, there is no enforceable deal. If the app generates significant revenue, memory of verbal agreements becomes unreliable. Get it in writing before a single line of code is transferred.

*Mitigation*: Even a one-page LOI signed by both parties is better than nothing while the formal agreement is drafted.

---

**2. Quarks underinvests in marketing, app dies quietly**
The most common failure mode for apps that "have a deal" is that the distribution partner doesn't put real money behind it. The app sits in the App Store with no downloads and quietly becomes shelfware.

*Mitigation*: The minimum investment commitment clause (Section 6 of the proposal). Without a defined floor, there's no accountability. If they won't commit to at least $5K in 90 days, that tells you something important about how seriously they're taking it.

---

**3. AI token costs balloon and become a dispute**
Professor Madrid is a heavy API consumer: speech-to-text, vision models, frontier conversation models, TTS. At even 100 active daily users with 10-minute sessions, you could be looking at $1,000–$3,000/month in API costs. At 1,000 DAU, this becomes $10,000+/month.

*Mitigation*: Be explicit that all token costs are Quarks's operational responsibility. The monthly economics should be modeled in the partnership discussion — you don't need to predict revenue, but both sides should understand the cost structure before committing.

Rough token cost estimate for context:
- GPT-4o for conversation: ~$0.005–0.015 per session
- Whisper for voice input: ~$0.006/minute
- TTS output: ~$0.015/1000 characters
- Vision (Street View): ~$0.003–0.01 per image

At 100 DAU with 15-min average sessions: ~$150–$600/month. At 1,000 DAU: $1,500–$6,000/month. Share this range with Quarks so there are no surprises.

---

**4. Code reuse / parallel release — undetectable, unenforceable without trust**
You acknowledged this: you cannot audit what Quarks does with the source code. A bad actor could reskin the app and release a clone under a different name.

*Mitigation*: This risk is mostly mitigated by the existing client relationship — they have reputation to lose. The legal clause creates liability if discovered. The real protection is choosing the right partner, which you've already done by picking someone you have a relationship with. Accept this residual risk as the price of doing a trust-based deal.

---

### MEDIUM SEVERITY

**5. Apple policy violations at review**
Apps using AI-generated voice, real-money subscriptions, and user-generated content face heightened App Store scrutiny. A rejection delays everything.

*Mitigation*: Review Apple's guidelines for AI apps and subscription terms before submitting. Have Quarks's legal review the privacy policy for compliance. Budget for 2 review cycles.

---

**6. Relationship damage if the deal goes wrong**
Quarks is an existing client. A failed partnership could cost you more than this app is worth.

*Mitigation*: The exit clause (Section 9) should be clean and non-acrimonious — it shouldn't feel like a trap for either side. The goal is that if this doesn't work, both parties walk away cleanly and the professional relationship survives.

---

**7. Revenue reporting opacity**
You will not be able to verify Quarks's revenue numbers without audit rights. They control the payment infrastructure.

*Mitigation*: The analytics access clause (Section 4) partially addresses this — App Store Connect revenue data is directly accessible and cannot be manipulated. Ensure your read-only access is to App Store Connect itself, not just a dashboard Quarks controls.

---

### LOWER SEVERITY

**8. Personnel disagreements slow development**
If Quarks hires a designer or project manager you can't work with, the approval clause helps — but could also become a friction point.

*Mitigation*: Frame the approval right as "code access only" initially. You don't need to approve marketing copywriters. Reserve the veto for people with repository access.

---

**9. Scope creep — Quarks wants features you can't build in agreed timeframe**
As soon as there's a financial partner, feature requests escalate. You could end up building their roadmap at your expense.

*Mitigation*: Define "ongoing development" loosely in the agreement — you commit to maintaining and improving the product at your professional judgment, not to delivering any specific feature on any specific date. Feature prioritization is a joint decision (Section 8).

---

## Market Rates — Developer Revenue Share Benchmarks

| Scenario | Creator's Share | Notes |
|---|---|---|
| Pure IP license (no ongoing work) | 5–15% | One-time transfer, creator walks away |
| License + light maintenance | 15–20% | Bug fixes only, no new features |
| **Transfer + active development** | **25–35%** | **This is your situation** |
| Co-founder with equity | 30–50% | Equity stake, not revenue share |
| Angel investment for cash | 10–20% equity | Cash in, no ongoing work |

**30% of Quarks's net revenue (after Apple's cut) is the right number.** It's within the market range for an active technical partner who is contributing an already-built, commercially viable product.

If they push back: 
- 30% is non-negotiable for the first 12 months while the product is unproven
- After month 12, if revenue is strong, you can offer to step down to 25% in exchange for a guaranteed minimum monthly payment (e.g., $500/month floor regardless of revenue)

---

## What to Ask Quarks in the First Meeting

1. What's your timeline expectation for launch? (Tests your alignment on urgency)
2. What marketing budget are you comfortable committing to in the first quarter?
3. Who internally at Quarks owns this project? (Need a named person, not "we")
4. Are you comfortable with my analytics access to App Store Connect directly?
5. Have you released an app on the App Store before? (Affects timeline risk)

---

## The One Thing That Will Make or Break This

**A named internal owner at Quarks with budget authority.**

If there's no single person at Quarks who owns this project and has the authority to approve spending, the partnership will stall. The enthusiasm of the initial conversation will not survive contact with internal procurement, legal, or management review. Get a name and a title before you invest more time in this.
