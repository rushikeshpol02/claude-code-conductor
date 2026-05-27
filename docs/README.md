# Claude Customizations — Explainer Docs

Plain-English explainers for the five interlocking systems defined in [`../CLAUDE.md`](../CLAUDE.md).

These docs are for **humans** (you, teammates, future-you). `CLAUDE.md` itself is the source of truth — it's what the model reads. These docs explain *why* each piece exists, what it solves, and how the pieces connect.

## The Five Systems (and one external piece)

| # | System | Location in CLAUDE.md | Explainer doc |
|---|---|---|---|
| 1 | **Effort Routing Framework** (Tiers) | L3–76 | [effort-routing.md](./effort-routing.md) ✅ |
| 2 | **Interaction Rules** | L78–84 | *(coming)* |
| 3 | **Plan Mode Standards** | L86–182 | [plan-mode-standards.md](./plan-mode-standards.md) ✅ |
| 4 | **AI Team (Persona Architecture)** | L184–557 | [persona-architecture.md](./persona-architecture.md) ✅ |
| 5 | **Memory Discipline** | L559–573 | [memory-discipline.md](./memory-discipline.md) ✅ |
| — | **Phase 3 Spawn-Audit Hook** (deterministic backstop) | `~/.claude/phase3-spawn-audit.py` + `settings.json` Stop array | *(coming)* |

## How These Systems Connect

The five systems are designed as one machine. Here's the dependency map:

```
                         USER PROMPT
                              │
                              ▼
                  ┌───────────────────────┐
                  │ EFFORT ROUTING (1)    │
                  │ Picks a Tier on line 1│
                  └──────┬────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
          Tier 1/2              Tier 3 / 4
              │                     │
              ▼                     ▼
        Single voice         ┌─────────────────┐
        Direct response      │ PERSONA TEAM (4)│
                             │ Auto-fires      │
                             │ Spawns multiple │
                             │ subagents       │
                             └──────┬──────────┘
                                    │
                                    ▼
                           ┌──────────────────┐
                           │ INTERACTION (2)  │
                           │ AskUserQuestion  │
                           │ when 3+ Qs       │
                           └──────┬───────────┘
                                  │
                                  ▼
                           ┌──────────────────┐
                           │ Final response   │
                           └──────┬───────────┘
                                  │
                                  ▼
                           ┌──────────────────┐
                           │ STOP HOOK fires  │
                           │ Audits spawn     │
                           │ behavior         │
                           └──────────────────┘

  PLAN MODE — separate sub-flow when planning is involved
                              │
                              ▼
                  ┌───────────────────────┐
                  │ PLAN MODE STANDARDS (3)│
                  │ 8 mandatory plan       │
                  │ sections + reviewer    │
                  │ persona spawn before   │
                  │ ExitPlanMode           │
                  └───────────────────────┘

  MEMORY — separate cross-session loop
                              │
                              ▼
                  ┌───────────────────────┐
                  │ MEMORY DISCIPLINE (5) │
                  │ End-of-session check  │
                  │ across 4 memory types │
                  │ Loaded at next        │
                  │ session start         │
                  └───────────────────────┘
```

### Key dependencies

- **System 1 → System 4:** The Tier framework decides whether the persona team fires. Tier 3+ automatically invokes it.
- **System 4 → System 2:** When the team needs to ask the user, it uses the AskUserQuestion tool (3+ questions rule).
- **System 3 → System 4:** Plan Mode Standard 7 requires spawning reviewer personas via `Agent()` before `ExitPlanMode` — same architecture, applied to a plan artifact.
- **System 4 ↔ Stop Hook:** The hook deterministically enforces that Tier 3+ declarations actually spawn the team. Bridges the probabilistic LLM-judges-itself gap that pure rules can't close.
- **System 5 is orthogonal** — fires at session boundaries, independent of which other systems were used during the session.

## Why interlocking, not modular

These pieces are designed to reinforce each other:

- The **Tier** declaration is the trigger that fires the **Persona Team**.
- The **Persona Team** uses **Interaction Rules** when it needs user input.
- **Plan Mode Standards** are basically the Persona Architecture applied to plan-time work.
- The **Stop Hook** is the only deterministic enforcement layer — without it, all the other systems are probabilistic.
- **Memory Discipline** keeps useful patterns across sessions so future invocations of all the other systems start with better context.

Pull one out and the others get weaker. That's why a single page exploring "all the customizations" was tempting — but reading 1000 lines of mixed content is harder than reading 5 focused docs that link to each other.

## Reading order (recommended)

If you're new to this setup, read in this order:

1. **effort-routing.md** — the entry point. Sets up the tier mental model.
2. **plan-mode-standards.md** — the simpler structured-work pattern.
3. **persona-architecture.md** — the biggest piece. Builds on Tier + Plan Mode.
4. **interaction-rules.md** — small piece. Mostly about AskUserQuestion timing.
5. **memory-discipline.md** — separate concern. Session-boundary mechanics.
6. **stop-hook.md** — the enforcement layer. Read last because it's about backstopping the rest.

## Source of truth

If anything in these docs contradicts CLAUDE.md, **CLAUDE.md wins**. These are explainers; CLAUDE.md is the spec. When CLAUDE.md changes, this folder should be updated to match.
