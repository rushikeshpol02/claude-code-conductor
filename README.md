# claude-code-conductor

Drop-in upgrades to `~/.claude/` that turn Claude Code into an orchestrator of multiple AI personas — adding tier-based effort routing, structured plan-mode discipline, and a deterministic Stop hook the LLM can't self-rationalize past.

**Requires:** bash 4+, Python 3.8+. Tested on macOS; should work on Linux with standard `python3`.

---

## Why this exists

Claude Code's default behavior works well for simple tasks. On complex work — code reviews, architecture decisions, multi-file refactors, plan-then-execute workflows — it tends to collapse multi-perspective analysis into a confident single-voice answer.

The failure mode is structural. When one model tries to think *"what would a PM say? what would an engineer say? what would security say?"* all in one head, it unconsciously resolves those conflicts before they surface. The disagreement mechanism that would have caught the real problem never fires.

A 14-day audit of one heavy user's Claude Code sessions found **66% of complex (Tier 3+) tasks ran single-voice** — the architectural disagreements that should have caught issues never showed up. This config closes that gap:

- **Effort matches task complexity** (lightweight for trivia, heavy for design work)
- **Multiple AI personas review independently** before any synthesis
- **Plans get structured discipline** before execution
- **A Stop hook catches** when the discipline didn't actually fire — running outside the LLM, so it can't be talked into compliance

> This was iterated from one user's sessions, not yet validated across teams. Adopt accordingly.

---

## What it adds

Six features, each independently installable. Pick a subset or take all.

### 1. Tier-based effort routing
Every response starts with `[Tier: Quick | Standard | Analytical | Deep — <reason>]`. Tier is auto-selected from intent keywords, files involved, and complexity.
**Solves:** Claude applying the same effort to "what does X mean" and "redesign this architecture." Trivial tasks get fast direct answers; complex tasks get the full machinery.

### 2. AI Team / Persona Architecture
On Tier 3+ tasks, Claude spawns multiple persona subagents in parallel (PM, Architect, Engineer + task-specific specialists like AI QA, Discovery Researcher, Security Reviewer). Each runs independently with isolated context; findings consolidate through a structured Finding Log.
**Solves:** single-voice convergence — when one model plays all the roles, it pre-resolves conflicts before you see them. Isolated subagents cannot silently agree with themselves.

### 3. Plan Mode Standards
Plans must contain 8 mandatory sections in order (Context, Clarifying Questions, Findings/Root Causes, Fixes, Prior Attempt Analysis, Pass 1 Justification, Pass 2 Coverage, Review Gate). Before `ExitPlanMode`, independent reviewer personas spawn for sign-off.
**Solves:** plans built on assumptions, fix justifications that hand-wave, plans that never see an independent review before execution.

### 4. Memory Discipline
Cross-session persistence across 4 memory types (user role / corrections / project state / external references) with an end-of-session check that captures what the model learned.
**Solves:** sessions starting cold every time, user corrections not sticking, having to re-establish context every chat.

### 5. Phase 3 Spawn-Audit Stop Hook
A ~140-line Python script wired into `~/.claude/settings.json`. Runs after every assistant turn. Checks that Tier 3+ declarations actually spawned the persona team via real `Agent()` calls — not inline single-voice simulation.
**Solves:** rules-only enforcement that the LLM rationalizes past. The hook runs outside the model's response generation, so it can't be talked into compliance.

### 6. Interaction Rules
`AskUserQuestion` tool required for 3+ clarifying questions (not bullet lists buried in prose).
**Solves:** model burying important decisions in text the user skims past.

---

## How to install

```bash
git clone https://github.com/rushikeshpol02/claude-code-conductor.git ~/claude-code-conductor
cd ~/claude-code-conductor
./install.sh --dry-run    # preview every change
./install.sh              # install all features (default)
```

### Install a subset

```bash
./install.sh --features=tier,memory       # just two features
./install.sh --features=plan-mode         # plan-mode only
./install.sh --features=hook              # auto-pulls personas + tier
```

Dependencies auto-resolve: `hook` requires `personas`, `personas` requires `tier`. Selecting one pulls in what it needs.

`--features=X,Y,Z` is **authoritative** — re-running with a different list installs new features AND removes ones previously installed but no longer in the list.

### Wire the Stop hook (if `hook` is installed)

After `install.sh`, add this object as a new element of your `~/.claude/settings.json` `hooks.Stop` array (alongside any existing entries — not replacing them):

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "/usr/bin/python3 ~/.claude/phase3-spawn-audit.py"
    }
  ]
}
```

See [`settings.json.template`](./settings.json.template) for the full surrounding structure. On non-macOS systems: run `which python3` and use that path. Then quit Claude Code completely and start a new session.

### Verify the hook works

```bash
cat > /tmp/test.jsonl << 'EOF'
{"type":"user","message":{"role":"user","content":"test"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"[Tier: Analytical — test]\nTask: Review & Critique | Personas: PM (lead), Architect, Engineer\n\nNo spawn..."}]}}
EOF
echo '{"session_id":"test","transcript_path":"/tmp/test.jsonl","stop_hook_active":false}' \
  | /usr/bin/python3 ~/.claude/phase3-spawn-audit.py
echo "exit code: $?"
rm /tmp/test.jsonl
```

Expected: a "Phase 3 spawn-audit FAILED" message + exit code `2`. If you get exit code `0`, the hook isn't catching violations — check the script path.

---

## Reference

### What's in the repo

| File / dir | Purpose |
|---|---|
| `CLAUDE.md` | Global Claude instructions (~575 lines). The source of truth — `install.sh` extracts sections from this file. |
| `personas/*.md` | 15 extended persona definitions loaded as subagents during Tier 3+ tasks. |
| `hooks/phase3-spawn-audit.py` | Stop hook script. |
| `settings.json.template` | Sanitized template (no real API keys). |
| `memory/MEMORY.md.template` | Empty memory index for new installs. |
| `install.sh` / `uninstall.sh` | Setup and teardown. |
| `docs/*.md` | Plain-English explainers for each customization system. Start with [`docs/README.md`](./docs/README.md). |

### What's NOT in the repo (and why)

- **`settings.json`** (the real file) — contains API keys and user-specific paths. Use the template + your own credentials.
- **Workspace memories** — `memory/*.md` is gitignored. Memories accumulate per-workspace and are personal.
- **Hook at `~/.claude/hooks/`** — that subdirectory is root-owned on some Claude Code installs. The Stop hook ships in `hooks/` here but is installed to `~/.claude/` root (sibling of `settings.json`).

### Install modes

| Mode | What it does to your CLAUDE.md |
|---|---|
| `--merge` (default) | Each selected feature gets its own marker block. Idempotent: re-runs refresh existing sections in place; features you don't select are removed. Personal content outside the markers stays untouched. |
| `--copy` | Replaces your `CLAUDE.md` with the repo's full content. Requires `--features=all`. Use only if you have no personal content. |

### Merge-mode behavior

| Your starting state | Result |
|---|---|
| No `~/.claude/CLAUDE.md` | Creates it, wrapped in per-feature markers |
| `CLAUDE.md` exists, no markers | Appends our marked sections to the bottom; your content stays untouched at the top |
| `CLAUDE.md` exists with our markers | Replaces content between markers with the latest repo version; everything outside stays |

`install.sh` only makes **copies** — nothing in `~/.claude/` depends on this repo's filesystem location. Move or delete the repo later and your config keeps working. To pick up updates: `git pull && ./install.sh`.

### Personas and the hook (skip-and-warn)

Persona files and the hook script use **skip-and-warn** behavior: if a target file exists with different content, your version is preserved and ours isn't installed. To wholesale replace them: remove your version (or `./uninstall.sh`), then re-install.

### Uninstalling

```bash
./uninstall.sh --dry-run
./uninstall.sh
```

Strips per-feature managed sections from `CLAUDE.md` (preserves your personal content outside markers). Removes persona files and hook that match the repo's content; locally modified files are preserved. **Manual step:** remove the Stop hook entry from `~/.claude/settings.json`.

### Updating

```bash
cd ~/claude-code-conductor
git pull
./install.sh    # re-run to refresh your ~/.claude/
```

### Customizing

- **Personal rules:** add them OUTSIDE the managed-section markers in your `~/.claude/CLAUDE.md`. They'll survive every re-install.
- **Project-specific:** add a `CLAUDE.md` to your project root. Claude Code loads it in addition to global.

---

## Known gaps

- **Tier 2 + persona-task-type bypass** — The Stop hook is silent for `[Tier: Standard]`. The architecture spec says Tier 2 + persona-task should still fire the team, but the hook doesn't detect this from the user's prompt. Workaround: declare `[Tier: Analytical]` explicitly.
- **Spawn-fidelity (property 2)** — The hook checks that personas were *spawned*, not that their findings actually drove the response. Citation-based enforcement was attempted and failed independent review across two design iterations.
- **Hook is user-writable** — Any process with write access to `~/.claude/phase3-spawn-audit.py` can disable enforcement by overwriting it with `sys.exit(0)`. No integrity check ships.

---

## License

MIT — see [LICENSE](./LICENSE).

## Acknowledgments

This config was iterated through a deep design session that audited adherence to the persona architecture over 14 days of one user's Claude Code sessions. The Stop hook was chosen over rules-only enforcement after rules-only attempts repeatedly failed independent reviewer scrutiny — deterministic shell execution escapes the honor-system trap that LLM-judges-itself rules can't.
