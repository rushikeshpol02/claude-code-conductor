#!/usr/bin/env bash
#
# uninstall.sh — Reverse what install.sh did.
#
# Removes:
#   - All per-feature managed sections (BEGIN/END claude-code-conductor:<feature>)
#     from ~/.claude/CLAUDE.md. User's personal content above/below the markers
#     is preserved. If the file becomes empty after stripping, it's removed.
#   - Legacy single-marker section (BEGIN/END claude-customizations managed
#     section) from older installs (kept for migration).
#   - Persona files in ~/.claude/personas/ that match the repo's content
#     (or are legacy symlinks into the repo). Locally modified files are kept.
#   - Stop hook ~/.claude/phase3-spawn-audit.py — same logic.
#
# WILL NOT touch:
#   - settings.json (you wire it yourself; see README.md)
#   - memory/ (workspace-owned)
#   - Personal content in CLAUDE.md outside the managed sections
#   - Persona files you've locally modified
#
# Use --dry-run to preview without making changes.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0

# Legacy single-marker (older installs)
LEGACY_BEGIN_MARKER="<!-- BEGIN claude-customizations managed section -->"
LEGACY_END_MARKER="<!-- END claude-customizations managed section -->"

# Per-feature marker prefix (used to find ALL managed sections regardless of feature name)
PER_FEATURE_BEGIN_PREFIX="<!-- BEGIN claude-code-conductor:"
PER_FEATURE_END_PREFIX="<!-- END claude-code-conductor:"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<EOF
Usage: uninstall.sh [--dry-run]

Reverses install.sh. Strips per-feature managed sections from CLAUDE.md
(and the legacy single-marker section from older installs). Removes
persona files and the Stop hook only if they match the repo's content
(symlinks into the repo from older installs are also removed).

WILL NOT touch:
  - settings.json
  - memory/
  - Personal content in CLAUDE.md outside the markers
  - Persona files you've locally modified

Manual cleanup after this script:
  - Remove the Stop hook entry from ~/.claude/settings.json
    (look for 'phase3-spawn-audit.py' in the Stop hooks array)
EOF
      exit 0 ;;
    *) echo "Unknown arg: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say() { echo "$@"; }

symlinks_into_repo() {
  local target="$1"
  if [[ -L "$target" ]]; then
    local link_target
    link_target="$(readlink "$target")"
    [[ "$link_target" == "$REPO_DIR/"* ]]
    return $?
  fi
  return 1
}

# Strip ALL claude-code-conductor managed sections from CLAUDE.md.
# Handles both legacy single-marker and per-feature markers.
strip_all_managed_sections() {
  local target="$TARGET_DIR/CLAUDE.md"
  [[ ! -f "$target" ]] && return

  # Check if anything to strip
  local has_legacy=0 has_perfeature=0
  grep -qF "$LEGACY_BEGIN_MARKER" "$target" 2>/dev/null && has_legacy=1
  grep -qF "$PER_FEATURE_BEGIN_PREFIX" "$target" 2>/dev/null && has_perfeature=1

  if [[ "$has_legacy" == "0" && "$has_perfeature" == "0" ]]; then
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$has_legacy" == "1" ]]; then
      say "  [dry-run] would strip legacy single managed section from: $target"
    fi
    if [[ "$has_perfeature" == "1" ]]; then
      say "  [dry-run] would strip all per-feature managed sections from: $target"
    fi
    return
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v legacy_begin="$LEGACY_BEGIN_MARKER" \
      -v legacy_end="$LEGACY_END_MARKER" \
      -v pf_begin="$PER_FEATURE_BEGIN_PREFIX" \
      -v pf_end="$PER_FEATURE_END_PREFIX" '
    BEGIN { in_section = 0 }
    # Per-feature begin marker (any feature name)
    index($0, pf_begin) == 1 { in_section = 1; next }
    # Per-feature end marker
    index($0, pf_end) == 1 { in_section = 0; next }
    # Legacy begin / end markers
    $0 == legacy_begin { in_section = 1; next }
    $0 == legacy_end   { in_section = 0; next }
    in_section == 0 { print }
  ' "$target" > "$tmp"

  # If resulting file is empty or whitespace-only, remove it entirely.
  if [[ ! -s "$tmp" ]] || [[ "$(grep -cE '^[^[:space:]]' "$tmp" || true)" == "0" ]]; then
    rm "$target"
    rm "$tmp"
    say "  removed (only contained managed sections): $target"
  else
    mv "$tmp" "$target"
    say "  stripped managed sections from: $target"
  fi
}

# Remove a file if it traces back to this repo.
remove_if_owned() {
  local target="$1"
  local repo_src="$2"
  if [[ ! -e "$target" && ! -L "$target" ]]; then return; fi
  if symlinks_into_repo "$target"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove legacy symlink: $target"
    else
      rm "$target"
      say "  removed legacy symlink: $target"
    fi
    return
  fi
  if [[ -f "$target" && -f "$repo_src" ]] && diff -q "$target" "$repo_src" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove: $target"
    else
      rm "$target"
      say "  removed: $target"
    fi
    return
  fi
  say "  skipped (not ours / locally modified): $target"
}

say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "DRY-RUN — no changes will be made."
fi
say "Uninstalling claude-code-conductor from $TARGET_DIR..."

# CLAUDE.md — strip all managed sections (legacy + per-feature)
strip_all_managed_sections

# personas/
if [[ -d "$REPO_DIR/personas" ]]; then
  for repo_persona in "$REPO_DIR/personas/"*.md; do
    name="$(basename "$repo_persona")"
    remove_if_owned "$TARGET_DIR/personas/$name" "$repo_persona"
  done
fi

# Stop hook
remove_if_owned "$TARGET_DIR/phase3-spawn-audit.py" "$REPO_DIR/hooks/phase3-spawn-audit.py"

say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "Dry-run complete. No changes made."
else
  say "Done."
  say ""
  say "Manual cleanup still needed:"
  say "  - Remove the Stop hook entry from ~/.claude/settings.json"
  say "    (look for the line with 'phase3-spawn-audit.py' in the Stop hooks array)"
  say "  - Restart Claude Code to drop the old config from memory"
fi
