# claude-code-conductor

Drop-in upgrades to `~/.claude/` that turn Claude Code into an orchestrator of multiple AI personas. Adds tier-based effort routing, a multi-persona team architecture (PM, Architect, Engineer + extended specialists), structured plan-mode standards, and a deterministic Stop hook that catches architecture violations. Designed for teams sharing a consistent Claude Code setup.

## What's in here

| File / dir | Purpose |
|---|---|
| `CLAUDE.md` | Global Claude instructions (~575 lines). Tier framework, persona architecture, plan-mode standards, memory discipline. |
| `personas/*.md` | 15 extended persona definitions (AI QA, Architect, Discovery Researcher, etc.) loaded as subagents during Tier 3+ tasks. |
| `hooks/phase3-spawn-audit.py` | Stop hook that enforces persona spawn fidelity. Blocks turns where Tier 3+ was declared but the team wasn't actually spawned. |
| `settings.json.template` | Sanitized settings.json template. Wire the hook in here (see setup). |
| `memory/MEMORY.md.template` | Empty memory index template. Memories accumulate per-workspace as you use Claude Code. |
| `install.sh` | One-command setup. Merges (default) or copies files into `~/.claude/`. Supports per-feature install via `--features=...`, plus `--dry-run` and `--force`. Generates merge notes when existing files differ. |
| `uninstall.sh` | Reverses `install.sh`. Strips per-feature managed sections from `CLAUDE.md` (and removes persona files / hook that match the repo's content). Locally modified files are preserved. |
| `docs/*.md` | Plain-English explainers for each customization system (Effort Routing, Persona Architecture, Plan Mode Standards, Memory Discipline). Read `docs/README.md` first for the connection map. |

## What's NOT in here (and why)

- **`settings.json`** (the real file) — contains API keys and user-specific paths. Use the template + your own credentials.
- **Workspace memories** — `memory/*.md` is gitignored. Memories are per-workspace and personal; only the empty index template ships.
- **`~/.claude/hooks/`** in active form — that subdirectory is root-owned on some Claude Code installs. The Stop hook script ships in `hooks/` here but is installed to `~/.claude/` root (sibling of `settings.json`).

## Quick install

```bash
git clone <repo-url> ~/claude-code-conductor
cd ~/claude-code-conductor
./install.sh --dry-run    # see exactly what will change first
./install.sh              # actually install (default: all features, merge mode)
```

By default, install.sh runs in **merge mode** with **all features** — it appends each customization system into your existing `CLAUDE.md` wrapped in per-feature managed-section markers. Your personal rules stay untouched.

**install.sh only makes copies** — nothing in `~/.claude/` depends on this repo's filesystem location. You can move or delete this repo later and your config will keep working. To pick up repo updates, re-run `./install.sh` after `git pull`.

### Per-feature install

Each customization system can be installed independently:

| Feature | What it gives you | Depends on |
|---|---|---|
| `tier` | Effort Routing Framework (Quick/Standard/Analytical/Deep) | — |
| `interaction-rules` | AskUserQuestion timing | — |
| `plan-mode` | 7 Plan Mode Standards + 8 mandatory plan-file sections | — |
| `personas` | AI Team / Persona Architecture + 15 persona files | `tier` |
| `memory` | Memory Discipline (cross-session learning) | — |
| `hook` | Phase 3 Spawn-Audit Stop hook (deterministic backstop) | `personas` |

Dependencies are **auto-resolved**: selecting `hook` automatically pulls in `personas` and `tier`. Selecting `personas` automatically pulls in `tier`.

```bash
./install.sh                                # default: all features
./install.sh --features=tier,memory          # just two features
./install.sh --features=plan-mode            # plan-mode only
./install.sh --features=hook                 # auto-pulls personas + tier
```

**Set semantics:** `--features=X,Y,Z` is **authoritative**. Re-running with a different list will install new features AND remove ones that were previously installed but aren't in the new list. (Run with `--dry-run` first to preview.)

### Install modes

Pick ONE (default is `--merge`):

| Mode | What it does to your CLAUDE.md |
|---|---|
| **`--merge`** (default) | Each selected feature gets its own marker block. Idempotent: re-runs refresh existing sections in place; features you don't select are removed. Your personal content outside the markers stays untouched. |
| `--copy` | Replaces your `CLAUDE.md` with the repo's full content. Requires `--features=all` (or omit `--features`). Use only if you have no personal content. |

### Helper flags

| Flag | Purpose |
|---|---|
| `--dry-run` | Show what would happen. Make no changes. **Run this first.** |
| `--force` | Proceed even if your existing `CLAUDE.md` differs (only applies in `--copy` mode). |

### How merge mode handles your CLAUDE.md

| Your starting state | Merge-mode behavior |
|---|---|
| No `~/.claude/CLAUDE.md` exists | Creates the file with our content wrapped in markers |
| `CLAUDE.md` exists, no markers | **Appends** our marked section to the bottom; your content stays untouched at the top |
| `CLAUDE.md` exists with our markers | **Replaces** content between the markers with the latest repo version; everything outside the markers stays |

This is the recommended mode for first-time users. You can run `./install.sh` after every `git pull` and your personal content is never at risk.

### How persona files and the Stop hook are handled (both modes)

Personas and the hook script are **always installed as copies** — they live independently in `~/.claude/` and won't break if you move or delete this repo. Skip-and-warn behavior protects local customizations:

- **File doesn't exist** → install a fresh copy
- **File content matches ours** → refresh (no-op)
- **File is a legacy symlink** (from an older install) → convert to a copy
- **File content differs** → **skip with warning**; your version preserved. Re-run after removing your version if you want ours.

If you want to wholesale replace them, run `./uninstall.sh` first (or remove the specific files), then re-install.

## Uninstalling

```bash
cd ~/claude-code-conductor
./uninstall.sh --dry-run    # preview what would be removed
./uninstall.sh              # actually uninstall
```

Behavior matches the install mode:

- **Merge-installed `CLAUDE.md`**: strips the content between our markers, leaving your personal content intact. If only our content was in the file, the file is removed entirely.
- **Copy-installed `CLAUDE.md`**: removes the copy if its content matches the repo's. Skips if you've locally modified it.
- **Legacy symlinks** (from older installs that used `--symlink` mode): removed cleanly.

For personas and the hook: same logic — only files that trace back to this repo are removed. Anything you locally modified is preserved.

**Manual step still required:** remove the Stop hook entry from `~/.claude/settings.json` (look for `phase3-spawn-audit.py` in the `Stop` hooks array).

## Settings.json setup (manual — has secrets)

After `install.sh` runs, wire the Stop hook into your `~/.claude/settings.json`:

1. If you have **no** existing `settings.json`: copy `settings.json.template` to `~/.claude/settings.json` and fill in any placeholders (or delete the `env` block if you don't use Langfuse).
2. If you **already have** a `settings.json`: add this entry to your existing `hooks.Stop` array:

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

3. Restart Claude Code (or start a new session) — hooks load at session start.

## Verifying the hook fires

The hook runs after every assistant turn but is silent unless a Tier 3+ task was declared without proper spawn behavior. To verify it's wired correctly:

```bash
# Manually test the hook with a synthetic violation:
cat > /tmp/test.jsonl << 'EOF'
{"type":"user","message":{"role":"user","content":"test"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"[Tier: Analytical — test]\nTask: Review & Critique | Personas: PM (lead), Architect, Engineer\n\nNo spawn..."}]}}
EOF
echo '{"session_id":"test","transcript_path":"/tmp/test.jsonl","stop_hook_active":false}' \
  | /usr/bin/python3 ~/.claude/phase3-spawn-audit.py
echo "exit code: $?"
rm /tmp/test.jsonl
```

Expected output: a "Phase 3 spawn-audit FAILED" message and exit code `2`. If you get exit code `0`, the hook isn't catching violations — check the script path.

## The frameworks at a glance

CLAUDE.md defines three interlocking systems:

### Effort Routing (Tiers)
Every response starts with `[Tier: <Quick|Standard|Analytical|Deep> — <reason>]`. Tier is set by intent keywords, file counts, complexity, and risk. Tier 3+ automatically invokes the persona architecture.

### Persona Architecture
On Tier 3+ tasks, the orchestrator spawns multiple persona subagents in parallel (PM, Architect, Engineer, plus task-type-specific extended personas like AI QA). Each runs independently with isolated context. Findings get consolidated through a Finding Log with disposition tags (Incorporated / Critical / Rejected / Escalated / BLOCKED). Synthesis is single-voice but driven by the spawned subagents' returns — never inline simulation.

The Phase 3 spawn-audit hook enforces this: if you declare personas on line 2 of a Tier 3+ response but don't actually spawn them via `Agent()` tool calls, the hook returns exit 2 and your next turn starts with a system reminder showing the violation.

### Plan Mode Standards
Plan-mode plans must contain 8 mandatory sections in order: Context, Clarifying Questions Surfaced, Findings/Root Causes, Fixes, Prior Attempt Analysis, Pass 1 (Justification Strength), Pass 2 (Coverage Completeness), Review Gate. Before `ExitPlanMode`, the orchestrator must spawn reviewer personas via `Agent()` — independent review per Standard 7.

## Known gaps

- **Tier 2 + persona-task-type bypass** — The hook is silent for `[Tier: Standard]`. CLAUDE.md L352 says persona-task types at Tier 2 should still fire the architecture, but the hook doesn't currently detect this from the user's prompt. Declaring `[Tier: Analytical]` explicitly is the workaround.
- **Property (2) — spawn results actually used in synthesis** — The hook checks spawn *count*, not whether the spawned subagents' findings actually drove the response. Citation-based enforcement was attempted and failed Standard 7 review (see commit history for the design iteration if curious).
- **Hook is user-writable** — Any process with write access to `~/.claude/phase3-spawn-audit.py` can disable enforcement by overwriting it with `sys.exit(0)`. No integrity check ships.

## Updating

```bash
cd ~/claude-code-conductor
git pull
./install.sh         # re-run to refresh content in your CLAUDE.md
```

If `CLAUDE.md` itself changes substantially, Claude Code picks up the new version at the next session start (it's loaded fresh each session).

## Customizing

The shipped `CLAUDE.md` is generic. To add team-specific or personal rules:

- **Personal:** edit `~/.claude/CLAUDE.md` directly (if you installed with `--copy`) or maintain a local override (if symlinked — you can replace the symlink with your own file).
- **Project-specific:** add a `CLAUDE.md` in your project repo. Claude Code loads project-level CLAUDE.md in addition to global.

## License

MIT.

## Acknowledgments

This config was iterated through a deep design session that audited adherence to the persona architecture over 14 days of session JSONL data. The Stop hook was chosen over rules-only enforcement after rules-only attempts repeatedly failed independent reviewer scrutiny — deterministic shell execution escapes the honor-system trap that LLM-judges-itself rules can't.
