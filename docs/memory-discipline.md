# Memory Discipline

*One of the customizations in [CLAUDE.md](../CLAUDE.md). Lines 559–573. Index: [README](./README.md).*

*Cross-session persistence so future conversations open with useful context already loaded. Orthogonal to Tier / Persona / Plan Mode — fires at session boundaries.*

## The Problem

Each Claude Code session starts fresh. Whatever the model learned about you, your work, your preferences, or your project during a long session gets lost when the session ends. Without explicit persistence:

- **The user corrects the same mistake repeatedly.** "You did X again — I told you last time to do Y." Pattern doesn't stick across sessions.
- **Context has to be re-established every time.** "I'm a PM working on this MyConnect project, the design system is at..." — repeated weekly.
- **Decisions get forgotten.** "We agreed last sprint that meal-break compliance is out of scope" — but the next session doesn't know that.
- **External resources go undocumented.** "Linear project INGEST tracks pipeline bugs" — the next session can't find it.
- **User-validated approaches get rediscovered.** "Yes, the single PR was the right call here" — useful judgment that gets forgotten if not saved.

The result: every session has to bootstrap context from scratch. Most of that bootstrap is wasted work the user has done before.

## The Solution

Define **4 memory types**, write small markdown files for each useful learning, and load them automatically at session start. Plus, force an end-of-session memory check so useful patterns from THIS session get saved before the next one.

### The 4 memory types

| Type | What goes here | Example trigger |
|---|---|---|
| **user** | Role, expertise, preferences, knowledge level | "I'm a data scientist focused on observability" |
| **feedback** | Corrections OR confirmed non-obvious approaches. Saved as a rule + Why + How to apply | "Don't mock the database in these tests — we got burned last quarter" |
| **project** | Ongoing work, decisions, goals, deadlines, context not in the code | "Merge freeze begins 2026-03-05 for mobile release cut" |
| **reference** | External systems and resources (Linear, Grafana, Slack channels, dashboards) | "Pipeline bugs tracked in Linear project INGEST" |

### Where memories live

```
~/.claude/projects/<encoded-workspace-path>/memory/
├── MEMORY.md                    # Index — loaded at session start (first 200 lines)
├── user_role.md
├── feedback_<topic>.md          # Per-feedback files
├── project_<initiative>.md      # Per-project files
└── reference_<system>.md        # Per-reference files
```

Each memory file has YAML frontmatter (name + description + type) and a body. The body for feedback/project memories must include `**Why:**` and `**How to apply:**` lines so future-you can judge edge cases.

`MEMORY.md` is the index — one line per memory file. Auto-loaded by Claude Code at session start (capped at first 200 lines / 25KB).

### The end-of-session check

Before every session ends, run this 4-question check:

1. Did I learn anything new about the user's role, preferences, or expertise? → **user** memory
2. Did the user correct my approach, OR confirm a non-obvious approach worked? → **feedback** memory
3. Did I learn about ongoing work, decisions, goals, or deadlines? → **project** memory
4. Did the user point to an external system, resource, or tool? → **reference** memory

If yes to any: write the memory file and update `MEMORY.md` before the session ends.
If no to all: explicitly confirm the check was run and nothing qualified — don't silently skip.

### Mid-session Tier 3+ re-read

For Tier 3 (Analytical) or Tier 4 (Deep) tasks specifically: re-read `MEMORY.md` and fetch any individual memory files whose description is relevant to the task topic. Don't rely on what loaded at session start — re-read to catch anything missed.

This catches the case where MEMORY.md grew long, the entry you need is past line 200, or the relevant memory was written after the session started.

### What NOT to save

The discipline includes explicit "don't save" cases (CLAUDE.md L590ish equivalent in the global file). The point is to keep memory high-signal:

- Code patterns, conventions, file paths, architecture — these are in the code, not in memory
- Git history / who-changed-what — `git log` is authoritative
- Debugging fix recipes — the fix is in the code; commit message has context
- Anything already in CLAUDE.md
- Ephemeral task state — in-progress work belongs in TodoWrite, not memory

These exclusions apply even when the user explicitly asks to save. If asked to "save the PR list," ask what was *surprising* or *non-obvious* about it instead — that's what's worth keeping.

## High-Level User Flow

```
SESSION START
       │
       ▼
┌──────────────────────────────────┐
│ MEMORY.md auto-loads             │
│ (first 200 lines / 25KB)         │
│ Individual memory files fetched  │
│ on-demand when descriptions      │
│ match the task                   │
└────────────┬─────────────────────┘
             │
             ▼
       SESSION RUNS
             │
   ┌─────────┴──────────┐
   │                    │
Normal             Tier 3 / 4 task
work               │
   │               ▼
   │       ┌──────────────────┐
   │       │ MID-SESSION      │
   │       │ Re-read MEMORY.md│
   │       │ Fetch relevant   │
   │       │ memory files     │
   │       └─────────┬────────┘
   │                 │
   └────────┬────────┘
            │
            ▼
   LEARN SOMETHING USEFUL?
   (user correction, decision, etc.)
            │
            ├──── Yes ──┐
            │           ▼
            │      ┌──────────────────┐
            │      │ Write memory     │
            │      │ file immediately │
            │      │ Update MEMORY.md │
            │      │ index            │
            │      └────────┬─────────┘
            │               │
            └────────┬──────┘
                     │
                     ▼
              SESSION ENDS
                     │
                     ▼
        ┌────────────────────────────┐
        │ END-OF-SESSION CHECK       │
        │ 4 questions:               │
        │ 1. user memory?            │
        │ 2. feedback memory?        │
        │ 3. project memory?         │
        │ 4. reference memory?       │
        │                            │
        │ Yes → write file + update  │
        │ index                      │
        │ All no → confirm check ran │
        └────────────┬───────────────┘
                     │
                     ▼
              NEXT SESSION
              Starts with this memory loaded
```

## Quick Examples

**Feedback memory written from a correction:**

> User: "stop summarizing what you just did at the end of every response, I can read the diff"
>
> → Save: `feedback_no_trailing_summary.md`
>
> Body: "This user wants terse responses with no trailing summaries.
> **Why:** explicit correction, 2026-05-14.
> **How to apply:** end responses at the work, not at a recap."

**Project memory written from a decision:**

> User: "the reason we're ripping out the old auth middleware is that legal flagged it for storing session tokens in a way that doesn't meet new compliance requirements"
>
> → Save: `project_auth_middleware_rewrite.md`
>
> Body: "Auth middleware rewrite is driven by legal/compliance, not tech debt cleanup.
> **Why:** session token storage doesn't meet new requirements (legal-flagged).
> **How to apply:** scope decisions should favor compliance over ergonomics."

**Reference memory written from a system mention:**

> User: "check the Grafana board at grafana.internal/d/api-latency — that's what oncall watches"
>
> → Save: `reference_oncall_latency_dashboard.md`
>
> Body: "grafana.internal/d/api-latency is the oncall latency dashboard. Check it when editing request-path code."

## Expected Outcome

- **Cross-session learning persists.** Corrections stick. Patterns the user confirmed worked are repeated automatically next session.
- **Context bootstrap is automatic.** Future sessions open already knowing your role, your project's state, and the external resources you use.
- **High-signal memory.** The "what not to save" discipline keeps MEMORY.md from bloating with low-value entries. Stays under the 200-line auto-load cap.
- **Audit trail of learnings.** Each memory has a date and a "why" line — you can review what was learned and when.
- **Mid-session re-read for big tasks.** Tier 3+ tasks specifically check memory to catch context that wasn't loaded at session start.

## What this connects to

- **[effort-routing.md](./effort-routing.md)** — Tier 3+ tasks trigger the mid-session memory re-read. Quick/Standard tasks don't.
- **[persona-architecture.md](./persona-architecture.md)** — Persona work often produces feedback memories (user-validated approaches by persona, or corrections to persona invocation patterns).
- **[plan-mode-standards.md](./plan-mode-standards.md)** — Plans frequently reference memory ("we agreed in 2026-05-12 that X is out of scope"). Memory entries become Section 1 (Context) inputs.

## Honest Limits

- **End-of-session check relies on the model running it.** If the session ends abruptly (window crash, network drop), the check doesn't fire. Anything learned that session is lost.
- **The 200-line / 25KB auto-load cap is real.** As memory grows, older entries fall outside the auto-load window. The mid-session re-read mitigates but doesn't eliminate — only relevant-description matches get pulled.
- **Workspace-scoped.** Memory is per-workspace (`~/.claude/projects/<encoded-path>/memory/`). Memories don't follow you across workspaces unless explicitly ported (`/port-conversation` skill).
- **Stop hook surfaces a reminder.** A SessionStart-side reminder fires for memory check, but compliance is still the model's responsibility. No deterministic enforcement that memories ACTUALLY get written when the check finds qualifying material.
- **Memory rot.** Project facts (current decisions, deadlines) drift over time. A memory written 2026-03-01 about "merge freeze on Thursday" doesn't say which Thursday. Periodic memory hygiene needed; auto-staleness detection is not built.
- **Subjective triggers.** "Did the user correct my approach" requires the model to recognize a correction. Subtle corrections (e.g., the user phrased something slightly differently the second time) can be missed.
