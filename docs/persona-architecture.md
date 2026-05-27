# AI Team — Persona Architecture

*One of the customizations in [CLAUDE.md](../CLAUDE.md). Lines 184–557. Index: [README](./README.md).*

*This is the biggest system. It fires automatically on Tier 3+ work (see [effort-routing.md](./effort-routing.md)).*

## The Problem

When you ask an LLM to do complex work — review a skill, design an architecture, audit a codebase — it tends to give you a confident-sounding single-voice answer. The problem is that "single-voice" hides a critical failure mode:

**One model playing multiple roles pre-resolves conflicts before surfacing them.**

If the LLM tries to think "what would a PM say? what would an engineer say? what would security say?" all inside one head, it unconsciously smooths over the disagreements between those perspectives. The bug a Red-Teamer would have caught gets dismissed because the same model is also playing the optimistic Designer. The user evidence a Discovery Researcher would have demanded gets waved away because the same model is also playing the time-pressured PM.

The disagreement mechanism never fires. Critical issues that one perspective would catch get lost.

**Symptoms:**

- Reviews that miss obvious problems (the right lens never showed up)
- Plans that look thorough but have a single load-bearing assumption no one stress-tested
- Designs that work for the typical case but break adversarially
- Confident answers to genuinely uncertain questions

## The Solution

Define personas explicitly, run each one as an **independent subagent** with isolated context, and force them to return findings independently before any synthesis happens. The orchestrator (Claude's main response thread) then consolidates their findings in a structured Finding Log and writes a single-voice final output — but driven by the subagents' actual returns, not by orchestrator's own pre-resolved reasoning.

**Key concept: Isolated subagents cannot converge silently.**

When PM, Architect, and Engineer are three separate Agent() calls, each with its own context, none of them sees the others' analysis. They can't unconsciously smooth over disagreements because they don't know what the others said until the orchestrator pulls all returns together. Conflicts surface explicitly in the Finding Log and get resolved using a typed hierarchy.

### Who's on the team

**3 core personas** (defined inline in CLAUDE.md, always available):

| Persona | Owns |
|---|---|
| **PM** | Problem clarity, success criteria, user impact, scope |
| **Architect** | System design, root cause analysis, structural soundness |
| **Engineer** | Execution, stress-testing designs against real LLM behavior |

**15 extended personas** (defined in `~/.claude/personas/*.md`, loaded as needed):

| Persona | Invoke when |
|---|---|
| AI QA / Red Teamer | Adversarial review of any skill, prompt, agent, or output |
| AI Evaluator | Rubric-based scoring, benchmark comparison |
| ML / Model Strategist | Model selection, context budget, cost-vs-quality |
| Discovery Researcher | 0-to-1 work, problem validation, JTBD, user research |
| Product Analyst | Success metrics, instrumentation, analytics |
| Growth Strategist | 1-to-100 work, activation, retention |
| Technical Feasibility Reviewer | Engineering constraints, complexity, hidden deps |
| Security & Compliance Reviewer | Threat modeling, privacy, regulatory |
| Data Engineer | Data pipelines, event tracking, schema quality |
| DevOps / Platform Engineer | CI/CD, deployment, operational reliability |
| Executive Comms Reviewer | Any output for CXO/VP/Director audience |
| Client Engagement Lead | Stakeholder strategy, client-facing framing |
| PM Coach | PM mentoring, capability development, skill-gap feedback |
| Talent & Hiring Lead | JDs, interview rubrics, hiring bar |
| Standards & Practices Lead | Governance, quality gates, scaling practices |

**Total: 18 personas.** Each has Owns / Anti-bloat rule / Personality / Blocks-progress-when fields. Each starts its response with `**<Persona Name> [Task: <specific question>]:**` so attribution is unambiguous in the Finding Log.

### How task type picks the team

The model identifies the task type (10 named patterns in CLAUDE.md L358–533) and pulls a pre-defined persona list for that task:

| Task type | Lead | Supporting personas |
|---|---|---|
| Troubleshoot | Architect | PM, Engineer, AI QA |
| Design New Skill/Agent | PM → Architect → Engineer (sequential) | + AI QA, ML Strategist |
| Review & Critique | Architect | PM, Engineer, AI QA, AI Evaluator |
| Refine / Improve | Architect | PM, Engineer, AI QA |
| AI Agent / End-to-End | PM + Architect (co-lead) | Engineer, AI QA, ML Strategist, Security |
| Create PM Deliverable | PM | Discovery Researcher, Product Analyst, Tech Feasibility, Exec Comms |
| Review PM Deliverable | PM | (same as Create + Client Engagement Lead if exec-facing) |
| 0-to-1 Discovery | Discovery Researcher → PM | Product Analyst, Tech Feasibility |
| PM Capability | PM Coach | Standards & Practices (or Talent & Hiring for JD work) |
| Technical Analysis | Architect + Tech Feasibility (co-lead) | Security, Data Engineer, DevOps (conditional) |

The lead is **predefined** by task type — runtime decision is just task-type detection. Get the task type right and the right team auto-fires.

### The 6-phase execution

Once the architecture fires (Tier 3+ trigger), every task runs through six phases:

| # | Phase | What happens |
|---|---|---|
| 1 | **Detect** | Orchestrator identifies task type. Pulls persona list from Task Types section. If the user explicitly named a persona ("you are an AI Architect"), that persona becomes the **lead** — but the full team still fires |
| 2 | **Gather** | Orchestrator reads all relevant artifacts BEFORE spawning. Personas need context provided, not discovered |
| 3 | **Analyse** | **Atomic spawn:** all personas spawn in ONE message, as parallel Agent() tool calls. Each persona gets its persona definition + the task + an evidence boundary. Each runs in isolation. Each returns findings independently |
| 4 | **Resolve** | Orchestrator builds a **Finding Log** table: `Finding \| Persona(s) \| Disposition \| Notes`. Every finding gets a disposition: **Incorporated**, **Critical**, **Rejected**, **Escalated**, or **BLOCKED**. Conflicts resolved using a typed hierarchy (factual / values / priority / scope / unresolvable) |
| 5 | **Synthesise** | Orchestrator (not the lead persona) writes the final output in single voice. The output is driven by findings marked Incorporated or Critical in the log |
| 6 | **Verify** | Loop 1: orchestrator self-check that Critical findings are accurately present in the output. Loop 2: corrections if any are missing. After two loops, surface remaining issues to the user as a single decision |

### The Finding Log dispositions

Every finding from every subagent must be classified. No silent rejections.

| Disposition | Meaning |
|---|---|
| **Incorporated** | Will be reflected in the final output. State where |
| **Critical** | Incorporated AND must be spot-checked in Phase 6 |
| **Rejected** | Will not appear in output. State explicit reason |
| **Escalated** | Requires user decision before proceeding. State what decision |
| **BLOCKED** | A persona's blocking condition fired. Stop entire task. Escalate with the exact condition |

### The canary mechanism (for extended personas)

When an extended persona is spawned, its prompt template requires it to **quote its Canary value verbatim** from its persona file before any analysis. The canary is a unique string per persona file (e.g., `myconnect-red-teamer-v1`) that proves the subagent actually read the file rather than reproducing from training memory. If the canary is missing on first spawn, the orchestrator re-spawns once with explicit "use your Read tool" instructions. If still missing, mark BLOCKED.

### Deterministic enforcement — the Stop hook

The biggest reliability risk in this architecture is Phase 3 atomic spawn: declaring personas on line 2 of the response but skipping the actual `Agent()` calls and falling back to inline single-voice analysis. A 14-day audit found this happening on **66% of Tier 3+ turns** — the spec was intact, but execution wasn't.

Rules-only enforcement in CLAUDE.md couldn't fix this: *the LLM that would violate is the same LLM that would judge it didn't.* So a small Stop hook runs **outside** the LLM after every assistant turn — script at `~/.claude/phase3-spawn-audit.py`, wired into `settings.json` as the third Stop-hook entry.

What it checks (deterministically, via shell):
- If line 1 declares `[Tier: Analytical|Deep]`, line 2 must contain `Personas: <names>`
- `Agent()` tool-call count in the turn must be ≥ declared persona count

On violation: exits 2, structured error message becomes a system reminder in the next turn. The model can't rationalize past `grep` and `re.match` — that's the point. **Catches the dominant failure mode (no spawn at all) but does NOT verify that spawned subagents' findings actually drove the synthesis** — that's the documented Property (2) gap below. Citation-based fidelity checks were attempted and failed independent review across two design iterations.

The hook is the only deterministic enforcement layer in the architecture. Every other rule is probabilistic.

## High-Level User Flow

```
USER PROMPT
     │
     ▼
┌──────────────────────────┐
│ TIER CLASSIFICATION      │  (see effort-routing.md)
│ Line 1: [Tier: ...]      │
└──────────┬───────────────┘
           │
   ┌───────┴────────┐
   │                │
Tier 1/2       Tier 3 / 4
   │                │
   ▼                ▼
Single voice    Architecture fires
                     │
                     ▼
        ┌────────────────────────────┐
        │ PHASE 1 — DETECT           │
        │ • Identify task type       │
        │ • Pull persona list        │
        │ • Honor user-named lead    │
        │ • Declare line 2:          │
        │   Task: X | Personas: ...  │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │ PHASE 2 — GATHER           │
        │ Read artifacts before      │
        │ spawning subagents         │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │ PHASE 3 — ATOMIC SPAWN     │
        │ ONE message with parallel  │
        │ Agent() calls.             │
        │ Each = a named persona.    │
        │ Each runs isolated.        │
        │                            │
        │  ┌───────┐  ┌───────┐  ... │
        │  │ PM    │  │ Arch  │      │
        │  │ Agent │  │ Agent │      │
        │  └───┬───┘  └───┬───┘      │
        │      │          │          │
        │      └─── findings ───┐    │
        └──────────────────────┼─────┘
                               │
                               ▼
        ┌────────────────────────────┐
        │ PHASE 4 — RESOLVE          │
        │ Pre-step: SPAWN AUDIT      │
        │   (declared == spawned?)   │
        │ Build Finding Log:         │
        │  Finding │ Persona │ Disp  │
        │ Resolve conflicts by type  │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │ PHASE 5 — SYNTHESISE       │
        │ Orchestrator writes final  │
        │ output. Single voice.      │
        │ Driven by findings.        │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │ PHASE 6 — VERIFY           │
        │ Loop 1: Find — are         │
        │   Critical findings in     │
        │   the output?              │
        │ Loop 2: Fix any gaps       │
        │ Then surface to user       │
        │ (max 2 loops, no Loop 3)   │
        └─────────────┬──────────────┘
                      │
                      ▼
                 USER OUTPUT
                      │
                      ▼
        ┌────────────────────────────┐
        │ STOP HOOK FIRES (post-turn)│  (see stop-hook.md when written)
        │ Verifies declared count    │
        │ matches spawned count.     │
        │ On mismatch: exit 2 →      │
        │ violation reminder in      │
        │ next turn.                 │
        └────────────────────────────┘
```

## Quick Examples

| User prompt | Task type | Lead | Team spawned |
|---|---|---|---|
| "Review my new skill file for issues" | Review & Critique | Architect | + PM, Engineer, AI QA, AI Evaluator (5 total) |
| "Design a new persona auto-loader" | Design New Skill/Agent | PM → Architect → Engineer | + AI QA, ML Strategist (6 total) |
| "Why is this prompt producing inconsistent output?" | Troubleshoot | Architect | + PM, Engineer, AI QA (4 total) |
| "Draft a PRD for the new dashboard" | Create PM Deliverable | PM | + Discovery Researcher, Product Analyst, Tech Feasibility (4 total) |
| "Mentor me on this user story" | PM Capability (Mentoring) | PM Coach | + Standards & Practices Lead (2 total) |
| "Analyze whether we can build this in 2 weeks" | Technical Analysis | Architect + Tech Feasibility | + others as conditions match |

## Expected Outcome

- **Multi-perspective analysis.** Each Tier 3+ task gets reviewed through 3–6 lenses, not one.
- **Conflicts surface.** When PM and Tech Feasibility disagree about timeline, that disagreement appears in the Finding Log and gets resolved explicitly — not silently averaged in the orchestrator's head.
- **Critical issues caught.** Adversarial lenses (AI QA / Red Teamer) catch failure modes that the optimistic lenses miss.
- **Decisions traceable.** Every output has a Finding Log behind it showing which findings shaped the result and which were rejected (with stated reasons).
- **Right-team-per-task.** PM tasks get PM-flavored teams. AI tasks get AI-flavored teams. No "one team fits all."

## What this connects to

- **[effort-routing.md](./effort-routing.md)** — the Tier framework decides *when* this architecture fires. Tier 3+ is the trigger.
- **[plan-mode-standards.md](./plan-mode-standards.md)** — applies the persona architecture to plan-time work. Standard 7 requires a pre-ExitPlanMode reviewer spawn.
- **The Stop hook** — covered in the *Deterministic enforcement* section above. Lives at `~/.claude/phase3-spawn-audit.py`; backstops Phase 3 atomic spawn.
- **[memory-discipline.md](./memory-discipline.md)** — feedback memories often record persona-related corrections (e.g., "user prefers Architect-lead on infrastructure tasks").

## Honest Limits

- **Property (2) — spawn results actually used in synthesis — is NOT enforced.** The Stop hook checks that personas were spawned (property 1). It does NOT check that the spawned subagents' findings actually drove the final synthesis. A clever model could spawn the team, ignore their returns, and write its own conclusions. Citation-based fidelity checks were attempted and failed Standard 7 review across two design iterations.
- **The orchestrator marks Critical dispositions.** Phase 6 verification depends on which findings got the Critical tag. Under-marking findings (calling everything "Incorporated") can reduce Phase 6's bite.
- **Tier 2 + persona task type bypass.** If the orchestrator mis-classifies a multi-persona task as Tier 2, the architecture doesn't fire and the hook is silent. Explicitly declaring `[Tier: Analytical]` is the workaround.
- **Spawn cost.** Spawning 4–6 parallel personas on every Tier 3+ task adds latency and tokens. Acceptable for high-stakes work; potentially heavy on borderline tasks. Tune by re-classifying as Tier 2 when warranted.
- **Persona file integrity.** The 15 extended persona files at `~/.claude/personas/` must stay intact and version-controlled. If they're deleted, modified, or get out of sync with the Persona Index in CLAUDE.md, the architecture degrades silently.
