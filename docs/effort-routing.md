# Effort Routing Framework

*One of the customizations in [CLAUDE.md](../CLAUDE.md). Lines 3–76. Index: [README](./README.md).*

## The Problem

LLMs treat every task with roughly the same effort. Ask "what's the capital of France?" and ask "redesign this skill pipeline" — by default, both get the same kind of thinking. That's wrong in two directions:

- **On trivial tasks**, the model wastes time and tokens doing unnecessary analysis. Slow and expensive.
- **On complex tasks**, the model gives a shallow answer that misses critical nuance. Wrong outputs that look right.

The user has no way to know, before reading the response, how much effort went into it. And the LLM has no forcing function that makes it stop and think: *"how big is this task, really?"*

The result: inconsistent quality. Sometimes great answers on hard problems, sometimes mediocre ones. Hard to predict which.

## The Solution

Force every response to declare its effort tier on the first line:

```
[Tier: <Quick | Standard | Analytical | Deep> — <one-line reason>]
```

Before generating any other output, the model evaluates the task across several signals and picks one of four tiers. The declaration is visible to the user and shows up in session logs for later auditing.

### The Four Tiers

| Tier | Used for | Files read | Files changed | Subagents | Clarifying questions |
|---|---|---|---|---|---|
| **Quick** | Direct answers, typo fixes, definitions | 0–1 | 0 | 0 | 0 |
| **Standard** | Single-step writing, reviewing, updating | 1–3 | 1–2 | 0 | 0–1 |
| **Analytical** | Multi-source analysis, audits, comparisons | 3–6 | 2–4 | per Task Type | 1–3 |
| **Deep** | Architecture, refactors, building from scratch | Unlimited | Unlimited | per Task Type | up to 5 |

### How the tier is chosen

The model looks at a scoring table that weighs:

- **Intent keywords** in the prompt — "what is" maps to Quick; "design", "build", "refactor" map to Deep
- **Number of files** the task involves
- **Complexity** — single concept vs. multi-system
- **Impact / risk** — is this a one-line fix or a decision that affects many things?

The highest-tier signal wins. So if the prompt has Quick keywords but touches 8 files, it's Deep.

### What the tier actually controls

| Parameter | Quick | Standard | Analytical | Deep |
|---|---|---|---|---|
| **Suggested model** | Haiku | Sonnet | Sonnet (deeper) | Opus |
| **Thinking depth** | None | Low | Medium | High |
| **Output format** | Direct answer | Structured doc | Reasoned recommendation | Full deliverable |
| **Risk section** | — | — | ✓ | ✓ |
| **Persona team fires** | — | — | ✓ | ✓ |

**User override:** Say "be quick on this" or "go deeper" — the override gets noted in the tier declaration.

> **Note on "Suggested model":** These are *cognitive depth targets*, not literal API model swaps. The session uses whichever Claude you started with; the model self-calibrates effort to the named depth. Real API-level routing (Haiku for Tier 1, Opus for Tier 4) would need a router upstream of Claude Code — not built here.

### Key rules

1. **Always declare on line 1. No exceptions.** Even Tier 1 trivial answers get a one-line `[Tier: Quick — ...]` tag.
2. **If scope changes mid-execution, re-declare:** `[Tier upgraded: Standard → Analytical — scope expanded to 5 files]` or `[Tier downgraded: Deep → Analytical — scope smaller than declared]`.
3. **Routing is autonomous by default.** But user can steer with phrases like "be quick on this" or "go deeper" — the override gets noted in the declaration.

## High-Level User Flow

```
USER PROMPTS
       │
       ▼
┌──────────────────────────────────┐
│ MODEL EVALUATES SIGNALS          │
│  • Intent keywords?              │
│  • How many files involved?      │
│  • How complex is the work?      │
│  • What's the impact / risk?     │
│  • User-stated override?         │
└────────────────┬─────────────────┘
                 │
                 ▼
       Highest-tier signal wins
                 │
       ┌─────────┴─────────┬──────────────┬──────────────┐
       │                   │              │              │
       ▼                   ▼              ▼              ▼
   ┌────────┐         ┌─────────┐    ┌─────────┐    ┌────────┐
   │ TIER 1 │         │ TIER 2  │    │ TIER 3  │    │ TIER 4 │
   │ Quick  │         │Standard │    │Analytic │    │ Deep   │
   └───┬────┘         └────┬────┘    └────┬────┘    └────┬───┘
       │                   │              │              │
       ▼                   ▼              ▼              ▼
  Direct answer       Structured     Reasoned rec    Full deliverable
  No risk check       doc with        with trade-     with rationale,
  No subagents        headers         offs            alternatives,
                                                       risks
                                      │              │
                                      └──────┬───────┘
                                             ▼
                                  ┌──────────────────────────────┐
                                  │ TIER 3+ AUTOMATICALLY FIRES  │
                                  │ THE PERSONA TEAM ARCHITECTURE │
                                  │ (line 2 declares Task +       │
                                  │  Personas; team spawns via    │
                                  │  parallel Agent() calls)      │
                                  └──────────────────────────────┘
                                             │
                                             ▼
                                  See persona-architecture.md
                                  for what happens next
       ───────────────────────────────────────────────────────────
                                  USER GETS RESPONSE
                                  (effort-appropriate)
```

## Quick Examples

| User prompt | Tier chosen | Why |
|---|---|---|
| "What does 'idempotent' mean?" | Quick | Definition lookup, 0 files, 1 concept |
| "Update this README section" | Standard | 1 file, single change, low risk |
| "Audit our 5 skill files for inconsistencies" | Analytical | 5 files, cross-document reasoning, decision-informing |
| "Design a new persona architecture for the team" | Deep | Multi-system, high stakes, unbounded |
| "Fix the typo" (after a big task) | Quick (with `Tier downgraded:` if mid-session) | Trivial scope |
| "Go deeper on this" | Whatever tier user steered to + override note | User override |

## Expected Outcome

- **Trivial questions get fast direct answers.** No paragraphs of analysis when one sentence will do.
- **Complex questions get the right machinery.** When you ask for something big, the model knows to spend the effort and bring in the persona team.
- **Effort is visible.** You can see the declaration on line 1 and know what to expect from the response.
- **Effort is auditable.** Every session log carries the tier tag, so you can later check whether the model called things correctly across a batch of work.

## What this connects to

- **Tier 3 and Tier 4 trigger the Persona Architecture.** See `persona-architecture.md` (when written) for what the team actually does once invoked.
- **Plan Mode inherits the tier of the work being planned.** See `plan-mode-standards.md` for the plan-time discipline.
- **The Stop hook at `~/.claude/phase3-spawn-audit.py`** checks Tier 3+ declarations against actual spawn behavior. If you declare Tier 3+ but skip the team, your next turn starts with a violation reminder.

## Honest Limits

- **Tier classification is the LLM's judgment.** It can mis-classify in either direction — calling something Quick when it really needed Analytical, or vice versa. The user override ("be quick" / "go deeper") is the explicit correction path.
- **Boundary cases are fuzzy.** "Review my PRD" could be Standard (review keyword) or Analytical (audit-ish). The persona-task-type detection at L361 tries to handle this, but it's not foolproof.
- **The framework is documentation-only.** No external check verifies the tier was set correctly. Only the Tier 3+ → spawn requirement has hook-based enforcement.
