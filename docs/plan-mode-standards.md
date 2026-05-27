# Plan Mode Standards

*One of the customizations in [CLAUDE.md](../CLAUDE.md). Lines 86–182. Index: [README](./README.md).*

*Plans are high-stakes artifacts. These standards make sure every plan is grounded, traceable, and independently reviewed before execution begins. Builds on [persona-architecture.md](./persona-architecture.md) at Standard 7.*

## The Problem

In Claude Code, you can enter "plan mode" before letting the model make changes. The intent is to align on the approach before code starts moving. But without discipline, plans frequently land with one or more of these defects:

- **Plan built on assumptions.** The model didn't read the actual artifacts — just inferred from your description. Plans look reasonable, but key facts are wrong.
- **Fix justifications are hand-waved.** "This fix should work" is not a why-it-works statement. When it fails, you have nothing to debug from.
- **Issues described in vague terms.** "The LLM doesn't follow this rule" instead of "Line 47 has no prohibition and Line 92 has a competing example."
- **Prior attempts ignored.** A new fix lands without considering why a previous fix at the same location didn't catch this case. Two fixes that compete.
- **No independent review.** The author of the plan is the same agent that judges the plan. The "I just thought of everything" trap.
- **Inconsistent structure.** No two plan files look alike. Hard to scan, hard to audit later.

The result: plans get approved that turn out to be partially wrong, requiring rework after execution starts.

## The Solution

Force every plan to meet **7 mandatory Standards** before execution can begin. The standards add structure, evidence-discipline, and independent reviewer perspective. Plans become uniform artifacts you can scan in 30 seconds, with a built-in audit trail.

### The 7 Standards

| # | Standard | What it requires |
|---|---|---|
| **1** | **Evidence First** | Read the actual artifacts before planning. Generated outputs, source files, eval reports. No description-only planning |
| **2** | **Clarifying Questions** | Surface 3 types of questions before analysis: context gaps, decision points, assumption confirmations. 3+ questions → use the AskUserQuestion tool. Cap at 5 per round |
| **3** | **Root Cause to File and Line** | Every issue traced to a specific file + line + reason. Never blame "the LLM" abstractly — name the missing rule, the loophole, the competing signal |
| **4** | **Fix Justification** | Every fix states *why* it works (not just what it does). Must include a testable constraint (a rule the LLM can verify against output). For competing-signal fixes, specifically address the competing signal |
| **5** | **Prior Attempt Analysis** | If previous fixes were made to the same files, state: what they targeted, why they didn't catch the current issue, how the new fix differs. If none: state "none — net-new work" |
| **6** | **Review Cycles + Mandatory Plan File Sections** | Two passes (Pass 1 Justification Strength, Pass 2 Coverage Completeness). Plus 8 mandatory sections in order in every plan file |
| **7** | **Review Gate** | Independent persona review before execution. Spawn reviewers via Agent() per Task Type. Exit criteria: 0 Critical + 0 Major findings. Minor findings shown to user for explicit acceptance |

### The 8 mandatory plan file sections

Every plan file must contain these in this order — Standard 6 enforces structure to prevent pro-forma stubs:

| # | Section | Testable constraint |
|---|---|---|
| 1 | **Context** | Must cite specific artifact paths + line numbers read before planning |
| 2 | **Clarifying Questions Surfaced** | Must list questions or state "none — no user-resolvable gaps." If 3+ questions exist, AskUserQuestion tool call MUST appear in the transcript |
| 3 | **Findings / Root Causes** | Each finding must cite file path + line number (or named section) |
| 4 | **Fixes** | Each fix must include a "Why it works" line with a testable constraint |
| 5 | **Prior Attempt Analysis** | Must state "none — net-new work" or name prior attempts with reason they didn't catch the current issue |
| 6 | **Pass 1 — Justification Strength** | Explicit named section. Check: is each justification weak? Strengthen with precise test or ❌ example from actual doc |
| 7 | **Pass 2 — Coverage Completeness** | Explicit named section. Check: every issue has a fix. Every fix doesn't introduce a new competing signal |
| 8 | **Review Gate** | Gate summary table including reviewer persona name + findings count |

**Section order is part of the constraint.** A plan with all 8 sections but in random order fails Standard 6.

### Severity rubric (used in Standard 7)

| Severity | Meaning |
|---|---|
| **Critical** | If this isn't resolved, execution will produce wrong output, break something, or require a major redo |
| **Major** | Execution can proceed but will produce a known gap or inconsistency needing a follow-up pass |
| **Minor** | Cosmetic, edge case, or low-impact — acceptable to carry with user awareness |

### Standard 7 — The Review Gate (the hardest one)

This is the one that closes the "I judge my own plan" trap. Before `ExitPlanMode`:

1. **Spawn reviewer personas via Agent()** based on Task Types section mapping:
   - Technical / AI plan → Architect + Engineer (+ AI QA / Red Teamer for skill/agent plans)
   - PM deliverable plan → PM + Technical Feasibility Reviewer (+ Discovery Researcher if problem framing in scope)
   - Mixed → both sets
2. **Reviewers return findings** with severity tags (Critical / Major / Minor).
3. **Findings get incorporated** into the plan file OR explicitly rejected with reason.
4. **Review Gate section (Section 8) is updated** with reviewer names + findings count.
5. **Exit criteria checked:**
   - 0 Critical findings unresolved ✓
   - 0 Major findings unresolved ✓
   - Minor findings listed and presented to user; user confirms acceptable
6. **Only then call ExitPlanMode.**

Calling ExitPlanMode without a documented reviewer spawn = architecture violation. Self-declaring "reviewed inline" doesn't satisfy this requirement.

## High-Level User Flow

```
USER ENTERS PLAN MODE
        │
        ▼
┌──────────────────────────────────┐
│ STANDARD 1 — Evidence First      │
│ Read actual artifacts            │
│ (no description-only planning)   │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 2 — Clarifying Questions│
│ Context gaps / decision points / │
│ assumption confirms              │
│ 3+ Qs → AskUserQuestion tool     │
│ Cap: 5 per round                 │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 3 — Root Cause          │
│ Trace each issue to file + line  │
│ Never "the LLM" abstractly       │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 4 — Fix Justification   │
│ Why each fix works               │
│ Testable constraint per fix      │
│ ❌/✅ examples from actual doc   │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 5 — Prior Attempts      │
│ Previous fixes? Why didn't they  │
│ catch this? How is new different?│
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 6 — Review Cycles +     │
│ 8 mandatory plan file sections   │
│ Pass 1: justification strength   │
│ Pass 2: coverage completeness    │
└────────────┬─────────────────────┘
             │
             ▼
┌──────────────────────────────────┐
│ STANDARD 7 — Review Gate         │
│ Spawn reviewer personas via      │
│ Agent() per Task Type mapping    │
│ Incorporate findings             │
│ Update Section 8                 │
└────────────┬─────────────────────┘
             │
             ▼
       ┌──────────────────┐
       │ EXIT CRITERIA    │
       │ Critical: 0 ✓    │
       │ Major: 0 ✓       │
       │ Minor: listed +  │
       │ user-confirmed   │
       └────────┬─────────┘
                │
        ┌───────┴───────┐
        │               │
       PASS            FAIL
        │               │
        ▼               ▼
   Gate summary    Iterate
   to user.        Standards 3–7
   "Confirm to     until gate
   proceed."       criteria met
        │
        ▼
   ExitPlanMode →
   execution begins
   (post-plan rule fires:
   re-invokes persona
   architecture for impl)
```

## Quick Examples

**Example plan section header that satisfies Standard 3:**

> ❌ "The LLM ignores the spawn rule."
>
> ✅ "L282 narrative warning ('STOP. Spawn instead.') has no testable check — relies on self-policing. Phase 4 audit at L301 catches violations post-hoc only."

**Example fix justification that satisfies Standard 4:**

> ❌ "This fix should prevent the issue."
>
> ✅ "Why it works: anchors enforcement to the only deterministic checkpoint plan mode has (ExitPlanMode tool call). Same pattern as Phase 4 spawn audit in the executed Persona plan — a self-detecting forcing function at a tool boundary. Testable: JSONL post-fix audit counts Agent() calls preceding each ExitPlanMode."

**Example Section 8 (Review Gate) that satisfies Standard 7:**

```
Plan review complete.
Critical issues: 0 ✅
Major issues: 0 ✅
Minor issues (unresolved): none

Reviewers: Architect, Engineer, AI QA / Red Teamer
Spawn audit: 3 declared, 3 returned. Canary verified.
Findings count: 6 (4 incorporated, 1 rejected with reason, 1 escalated)
```

## Expected Outcome

- **Plans are grounded.** Every plan cites the specific files read and the line numbers of issues. No "I think the issue is..." plans.
- **Fixes are justified.** Each fix has a testable why-it-works that you can verify after execution. Failed fixes are debuggable.
- **Plans are uniform.** Every plan file has the same 8 sections in the same order. Scannable in 30 seconds.
- **Independent review happens automatically.** You don't have to manually invoke "you are an Engineer, review this." Standard 7 spawns the reviewers before ExitPlanMode.
- **Audit trail is built in.** Section 8 records who reviewed, how many findings, and which got incorporated/rejected/escalated.
- **Surprises are caught upstream.** Standard 2's clarifying-question discipline + Standard 7's reviewer spawn surface issues during plan time, not after execution starts.

## What this connects to

- **[effort-routing.md](./effort-routing.md)** — Plan Mode inherits the tier of the work being planned. Tier 3 → Analytical plan with reviewer spawn. Tier 4 → Deep plan with the full team.
- **[persona-architecture.md](./persona-architecture.md)** — Standard 7's reviewer spawn IS the persona architecture applied to plan-time work. Same Agent() spawn pattern, same Task Type → reviewer mapping.
- **Stop Hook** *(coming)* — `~/.claude/phase3-spawn-audit.py` enforces that the reviewer spawn actually happens. If you call ExitPlanMode without `Agent()` calls in the same turn, the next turn starts with a violation reminder.
- **Post-plan execution rule** (CLAUDE.md L350) — when the user approves a plan with "execute" / "proceed", execution treats itself as a new task at the same tier. Re-invokes the persona architecture for implementation review.

## Honest Limits

- **Standard 2's "3+ questions" rule is judgment-based.** The model decides whether something is "a question that materially changes the plan" vs "a preference question that doesn't." Under-declaring questions bypasses the AskUserQuestion requirement.
- **Section 8 reviewer attribution can be gamed.** The model writes "Reviewers: Architect, Engineer" but the actual spawn count is what matters. The Stop hook checks spawn count, not the Section 8 text.
- **Severity (Critical / Major / Minor) is the orchestrator's call.** Under-marking findings can let a plan pass the gate when it shouldn't. The plan agent's findings should drive severity, but the orchestrator merges them.
- **Plans about plans get recursive.** Reviewing this very framework requires applying the framework. Worked in this session, but the recursion can become a productivity tax on small plans. Engineer's anti-bloat rule applies: surgical plans don't need the full machinery if the work is one-line and obvious.
- **No external validation that the 8 sections are present.** The Stop hook checks spawn behavior, not plan file structure. A plan with missing sections still slips through unless a reviewer catches it.
