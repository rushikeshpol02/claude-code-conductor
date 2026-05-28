# Contributing to claude-code-conductor

Quick reference for adding to this repo. Brief on purpose — the goal is to keep the spirit of the architecture (rigor over reflex) without burying contributors in process.

## Scope of the repo

This repo configures Claude Code globally (`~/.claude/`). Anything that fits the theme — *making Claude Code less reactive and more rigorous, out of the box* — is welcome. Anything project-specific or one-off belongs in a project-level `CLAUDE.md`, not here.

## Before you edit

1. **Read the docs.** `docs/README.md` has the connection map. Each system has its own explainer.
2. **Check the spec.** `CLAUDE.md` is the source of truth. The docs/ explain it; they don't override it.
3. **Run the install.sh dry-run.** `./install.sh --dry-run` shows exactly what your change would do to a teammate's `~/.claude/`.

## Adding a new feature

A "feature" here is a top-level section of `CLAUDE.md` (e.g., Effort Routing, Plan Mode, Memory) plus any external artifacts (persona files, hook scripts, etc.).

1. **Add the section to `CLAUDE.md`** as an `## ` heading. Pick a name that's unique and won't collide with future additions.
2. **Register the feature in `install.sh`** — add it to four places:
   - `ALL_FEATURES` (canonical order, controls assembly in user's CLAUDE.md)
   - `feature_section()` — map feature name → `## ` heading
   - `feature_dep()` — declare any dependencies (e.g., `personas → tier`)
   - `feature_label()` — human-readable label for messages
3. **Write an explainer** at `docs/<feature-name>.md` following the existing template: *Problem → Solution (with light details) → High-Level User Flow → Quick Examples → Expected Outcome → What this connects to → Honest Limits*.
4. **Update the README** — add a row to the per-feature table.
5. **Add an entry to `CHANGELOG.md`** under `[Unreleased]`.

## Testing changes

Before committing, run install.sh against a throwaway target to verify behavior:

```bash
# Dry-run against a clean target
rm -rf /tmp/test-claude && mkdir -p /tmp/test-claude
CLAUDE_HOME=/tmp/test-claude ./install.sh --dry-run

# Real install
CLAUDE_HOME=/tmp/test-claude ./install.sh

# Subset install with your new feature
CLAUDE_HOME=/tmp/test-claude ./install.sh --features=<your-feature>

# Idempotent re-run check (markers should stay at 1 each)
CLAUDE_HOME=/tmp/test-claude ./install.sh

# Feature-drop check (your feature should disappear)
CLAUDE_HOME=/tmp/test-claude ./install.sh --features=tier

# Uninstall round-trip
CLAUDE_HOME=/tmp/test-claude ./uninstall.sh
```

If any of these produce unexpected output, fix install.sh before sending the PR.

## Commit style

- One logical change per commit
- Subject line in imperative mood ("Add X", not "Added X")
- Subject ≤ 70 chars
- Body explains *why*, not *what* — the diff shows the what
- Co-Authored-By trailer if Claude wrote part of it

## What NOT to add

- **User-specific or project-specific rules.** These belong in a project-level `CLAUDE.md`. The global config should be team-agnostic.
- **Rules without a testable check.** If the LLM is the judge of its own compliance, the rule will drift. Either anchor it to a tool-call checkpoint or a hook, or don't add it. (See the design history in `docs/persona-architecture.md` — the citation-based fidelity check failed two rounds of review for exactly this reason.)
- **Verbose explanations to "make rules clearer."** More words ≠ more compliance. The anti-bloat rule in the Engineer persona applies to the repo itself: the cheapest fix is usually a deletion or one well-placed line.

## When to open a PR vs an Issue

- **PR:** you have a concrete change to propose
- **Issue:** you've spotted a problem but aren't sure how to fix it, or you want to discuss before coding

## Releasing

Maintainer-only. After merging changes to `main`:

1. Update `CHANGELOG.md` — move `[Unreleased]` items into a new version section with today's date
2. Commit the changelog update
3. `git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"`
4. `git push origin main && git push origin vX.Y.Z`

Use semver: bump minor for new features, patch for fixes, major when changing install behavior in a non-backward-compatible way.
