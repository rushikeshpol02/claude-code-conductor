# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`tool-use-discipline` feature** — 7th installable feature. Adds a `## Tool Use Discipline` section to `CLAUDE.md` instructing the model to compose read-only recon bash calls (`cd`, `ls`, `find`, `grep`, `cat`, `head`, `tail`, `wc`, `git status/log/diff`, `which`) into a single shell invocation when they share context. Sequential-dependent work, destructive ops, and parallel independent recon remain separate. Reduces chat clutter from consecutive expanded bash blocks.
- Origin: 14-day JSONL audit of one user's sessions (1,200 bash calls / 78 sessions, 72% recon-verb share, max consecutive streak of 27). Designed via a 3-persona team review (Architect / PM / Engineer).
- Known limit: the Bash tool's own system prompt encourages parallelism for speed — this CLAUDE.md rule is an undertuned counterweight. Expect ~60–70% reduction in consecutive recon bash blocks, not a full fix.

## [0.1.0] — 2026-05-28

First public release. Adds rigor to Claude Code: structured deliberation, multi-perspective AI review, and deterministic backstops the LLM can't self-rationalize past.

### Added

- **CLAUDE.md framework** — global instructions covering five interlocking systems:
  - **Effort Routing (Tiers)** — Quick / Standard / Analytical / Deep, declared on line 1 of every response
  - **Interaction Rules** — `AskUserQuestion` tool required for 3+ clarifying questions
  - **Plan Mode Standards** — 7 standards + 8 mandatory plan-file sections, with Standard 7 requiring independent persona review before `ExitPlanMode`
  - **AI Team / Persona Architecture** — 3 core personas (PM, Architect, Engineer) + 15 extended personas, 6-phase execution (Detect → Gather → Analyse → Resolve → Synthesise → Verify), Finding Log with disposition tags, canary mechanism for extended persona file reads
  - **Memory Discipline** — 4 memory types (user / feedback / project / reference) + end-of-session check + mid-session re-read on Tier 3+ tasks
- **15 extended persona files** in `personas/` — AI QA / Red Teamer, AI Evaluator, ML / Model Strategist, Discovery Researcher, Product Analyst, Growth Strategist, Technical Feasibility Reviewer, Security & Compliance Reviewer, Data Engineer, DevOps / Platform Engineer, Executive Comms Reviewer, Client Engagement Lead, PM Coach, Talent & Hiring Lead, Standards & Practices Lead
- **Phase 3 Spawn-Audit Stop hook** (`hooks/phase3-spawn-audit.py`) — deterministic check that runs after every assistant turn and fails the turn if Tier 3+ was declared but the persona team wasn't actually spawned via parallel `Agent()` calls
- **`install.sh`** with three modes:
  - `--merge` (default) — appends each selected feature into the user's existing `CLAUDE.md` wrapped in per-feature managed-section markers; idempotent on re-run; user content outside markers preserved
  - `--copy` — replaces `CLAUDE.md` with the repo's full content (whole-file overwrite; requires `--features=all`)
  - `--dry-run` — preview without making changes
- **`--features` flag** — per-feature install with auto-resolved dependencies (`hook` → `personas` → `tier`). Set semantics: `--features=X,Y,Z` is authoritative — re-running installs new features and removes previously-installed ones not in the new list.
- **`uninstall.sh`** — strips per-feature managed sections from CLAUDE.md, removes persona files / hook that match the repo's content. Locally modified files are preserved.
- **Skip-and-warn** behavior for persona files and the hook — if a target file exists with different content, the user's version is preserved and ours is not installed for that file.
- **Backup folder** at `~/.claude/.backup-<timestamp>/` with auto-generated `MERGE_NOTES.md` when replacing content.
- **`docs/` explainer folder** — plain-English explainers for each customization system:
  - `docs/README.md` — index + "how these systems connect" map
  - `docs/effort-routing.md`
  - `docs/persona-architecture.md` (includes inline Stop hook explainer)
  - `docs/plan-mode-standards.md`
  - `docs/memory-discipline.md`
- **`settings.json.template`** — sanitized template with placeholders for Langfuse keys and user-specific paths.
- **`memory/MEMORY.md.template`** — empty memory index for new installs.

### Changed

- **Stop hook explainer inlined** into `persona-architecture.md` and `plan-mode-standards.md` instead of being its own document. Rationale: the hook is enforcement infrastructure, not a standalone conceptual system.

### Removed

- **`--symlink` install mode** — nothing in `~/.claude/` should depend on this repo's filesystem location. Symlinks are durable only as long as the repo stays at the same path. Personas and the hook are now always installed as copies; legacy symlinks from earlier installs are auto-converted on re-run.

### Migration notes

- **Legacy single-marker installs** (from earlier development): `install.sh` and `uninstall.sh` still recognize the old `<!-- BEGIN claude-customizations managed section -->` markers and auto-migrate them to the new per-feature format on re-run.
- **Repo renamed** from `claude-customizations` to `claude-code-conductor`. If you cloned under the old name, you can either:
  1. `mv ~/claude-customizations ~/claude-code-conductor` and update your git remote, or
  2. Re-clone fresh.

[Unreleased]: https://github.com/rushikeshpol02/claude-code-conductor/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rushikeshpol02/claude-code-conductor/releases/tag/v0.1.0
