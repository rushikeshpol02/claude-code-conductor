#!/usr/bin/env bash
#
# uninstall.sh — Reverse what install.sh did.
#
# Behavior depends on what install.sh did to your CLAUDE.md:
#   - --merge install:    Removes the managed section between markers.
#                         Your content above/below the markers stays.
#   - --symlink install:  Removes the symlink. Restore from backup if you want.
#   - --copy install:     Removes the copy (if it matches the repo's content).
#
# Personas + hook: removes only files that this repo owns (symlinked here,
# or copies with content matching). Anything you modified is left alone.
#
# Will NEVER touch:
#   - settings.json    (you wire it yourself)
#   - memory/          (workspace-owned)
#   - Personal content above/below the managed section in CLAUDE.md
#
# Use --dry-run to preview without making changes.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0

BEGIN_MARKER="<!-- BEGIN claude-customizations managed section -->"
END_MARKER="<!-- END claude-customizations managed section -->"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<EOF
Usage: uninstall.sh [--dry-run]

Reverses install.sh based on how it installed:
  - --merge installs:   strips the managed section between markers from
                        CLAUDE.md. Your content above/below stays.
  - --symlink installs: removes the symlink to the repo.
  - --copy installs:    removes the copy (if it matches the repo's content).

For persona files and the hook: only removes files this repo owns
(symlinks pointing here, or copies with exactly matching content).
Anything you locally modified is preserved.

WILL NOT touch:
  - settings.json
  - memory/
  - Personal content in CLAUDE.md outside the managed section

Manual cleanup still needed:
  - Remove the Stop hook entry from ~/.claude/settings.json
EOF
      exit 0 ;;
    *) echo "Unknown arg: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say() { echo "$@"; }

# Check if a path is a symlink into our repo.
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

# Remove a single file if it traces back to this repo.
remove_if_owned() {
  local target="$1"
  local repo_src="$2"
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return
  fi
  if symlinks_into_repo "$target"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove symlink: $target"
    else
      rm "$target"
      say "  removed symlink: $target"
    fi
    return
  fi
  if [[ -f "$target" && -f "$repo_src" ]] && diff -q "$target" "$repo_src" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove copy: $target"
    else
      rm "$target"
      say "  removed copy: $target"
    fi
    return
  fi
  say "  skipped (not ours / locally modified): $target"
}

# Strip the managed section from CLAUDE.md (merge-mode uninstall).
strip_managed_section() {
  local target="$TARGET_DIR/CLAUDE.md"
  if [[ ! -f "$target" ]]; then
    return
  fi
  if ! grep -qF "$BEGIN_MARKER" "$target" 2>/dev/null; then
    return  # no markers, nothing to strip
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would strip managed section from: $target"
    return
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    BEGIN { in_section = 0 }
    $0 == begin { in_section = 1; next }
    $0 == end   { in_section = 0; next }
    in_section == 0 { print }
  ' "$target" > "$tmp"

  # If the resulting file is empty (only had managed section) → delete the file
  if [[ ! -s "$tmp" ]] || [[ "$(grep -cE '^[^[:space:]]' "$tmp" || true)" == "0" ]]; then
    rm "$target"
    rm "$tmp"
    say "  removed (only contained managed section): $target"
  else
    mv "$tmp" "$target"
    say "  stripped managed section from: $target"
  fi
}

say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "DRY-RUN — no changes will be made."
fi
say "Uninstalling claude-customizations from $TARGET_DIR..."

# CLAUDE.md — try merge-mode strip first; if no markers, try symlink/copy removal
if [[ -f "$TARGET_DIR/CLAUDE.md" ]] && grep -qF "$BEGIN_MARKER" "$TARGET_DIR/CLAUDE.md" 2>/dev/null; then
  strip_managed_section
else
  remove_if_owned "$TARGET_DIR/CLAUDE.md" "$REPO_DIR/CLAUDE.md"
fi

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
