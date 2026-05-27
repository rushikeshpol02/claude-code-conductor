#!/usr/bin/env bash
#
# install.sh — Wire claude-customizations into ~/.claude/
#
# Modes (choose ONE; default is --merge):
#   --merge      Append our CLAUDE.md content into your existing one,
#                wrapped in managed-section markers. Idempotent: re-runs
#                replace the content between markers in place. Your own
#                rules above/below the markers are preserved forever.
#                CANNOT be combined with symlink behavior.
#
#   --symlink    Replace your CLAUDE.md with a symlink to the repo's version.
#                `git pull` propagates updates automatically. Your existing
#                CLAUDE.md content is backed up but NOT merged.
#
#   --copy       Copy the repo's CLAUDE.md over yours (snapshot at install time).
#                Re-run install.sh to update. Your existing content backed up.
#
# Behavior across all modes:
#   - Persona files: skip-and-warn if you have a file with the same name and
#     different content. The hook script: same skip-and-warn.
#   - Existing files we replace get backed up to ~/.claude/.backup-<timestamp>/
#   - A MERGE_NOTES.md is generated in the backup folder when content differs.
#
# Helper flags:
#   --dry-run   Show what would happen, make no changes.
#   --force     Suppress halt-on-diff in --symlink/--copy modes.

set -euo pipefail

# --- config ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CLAUDE_HOME:-$HOME/.claude}"
MODE="merge"   # default
DRY_RUN=0
FORCE=0
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$TARGET_DIR/.backup-$TIMESTAMP"

# Markers for --merge mode. HTML comments are invisible in rendered markdown
# but unambiguous to grep.
BEGIN_MARKER="<!-- BEGIN claude-customizations managed section -->"
END_MARKER="<!-- END claude-customizations managed section -->"

# --- args ---
for arg in "$@"; do
  case "$arg" in
    --merge)   MODE="merge" ;;
    --symlink) MODE="symlink" ;;
    --copy)    MODE="copy" ;;
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --help|-h)
      cat <<EOF
Usage: install.sh [--merge|--symlink|--copy] [--dry-run] [--force]

  --merge      (DEFAULT) Append our CLAUDE.md content into your existing
               one inside managed-section markers. Idempotent on re-run.
               Your personal rules above/below the markers are preserved.
               Run install.sh again after 'git pull' to update.

  --symlink    Replace ~/.claude/CLAUDE.md with a symlink to the repo's
               version. Auto-updates on 'git pull'. Your existing content
               is backed up but NOT merged.

  --copy       Copy the repo's CLAUDE.md over yours. Snapshot at install
               time; re-run install.sh to update. Existing content backed up.

  --dry-run    Show what would happen. Make no changes. Always safe.
  --force      In --symlink/--copy modes only: proceed even if your
               existing CLAUDE.md differs substantially from the repo's.

Across all modes:
  - Persona files (~/.claude/personas/*.md): skip-and-warn if a file with
    the same name already exists with different content. Your version is
    preserved; ours is not installed for that file.
  - Stop hook (~/.claude/phase3-spawn-audit.py): same skip-and-warn.

Files replaced get backed up to ~/.claude/.backup-<timestamp>/. A
MERGE_NOTES.md file is generated when content differs.

settings.json is NOT installed — see README.md for manual steps (it
contains API keys and user-specific paths).
EOF
      exit 0 ;;
    *) echo "Unknown arg: $arg (try --help)" >&2; exit 1 ;;
  esac
done

# --- guard ---
if [[ ! -d "$REPO_DIR/personas" ]] || [[ ! -f "$REPO_DIR/CLAUDE.md" ]]; then
  echo "ERROR: this script must run from the claude-customizations repo root." >&2
  echo "       Current REPO_DIR=$REPO_DIR" >&2
  exit 1
fi

# --- helpers ---
say() { echo "$@"; }

# Returns 0 if a symlink points into our repo; 1 otherwise.
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

# Generic file-replace install for symlink/copy modes. Used for personas + hook.
backup_path_for() {
  local target="$1"
  local rel="${target#$TARGET_DIR/}"
  echo "$BACKUP_DIR/$rel"
}

backup_if_exists() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would back up: $target"
    else
      mkdir -p "$BACKUP_DIR"
      local backup_path
      backup_path="$(backup_path_for "$target")"
      mkdir -p "$(dirname "$backup_path")"
      mv "$target" "$backup_path"
      say "  backed up: $target -> $backup_path"
    fi
  fi
}

# Used for persona files and hook script (skip-and-warn mode).
install_with_skip_warn() {
  local src="$1"
  local dst="$2"
  # File doesn't exist → install fresh
  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      [[ "$MODE" == "symlink" || "$MODE" == "merge" ]] && say "  [dry-run] would symlink: $dst -> $src" || say "  [dry-run] would copy: $src -> $dst"
    else
      mkdir -p "$(dirname "$dst")"
      if [[ "$MODE" == "copy" ]]; then
        cp "$src" "$dst"
        say "  copied:    $src -> $dst"
      else
        # merge & symlink modes both symlink the per-file artifacts (personas + hook)
        ln -s "$src" "$dst"
        say "  symlinked: $dst -> $src"
      fi
    fi
    return
  fi
  # Symlink into our repo from a prior install → replace silently
  if symlinks_into_repo "$dst"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would refresh symlink: $dst"
    else
      rm "$dst"
      if [[ "$MODE" == "copy" ]]; then
        cp "$src" "$dst"
      else
        ln -s "$src" "$dst"
      fi
      say "  refreshed: $dst"
    fi
    return
  fi
  # Plain file with matching content → safe to replace
  if [[ -f "$dst" ]] && diff -q "$dst" "$src" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would replace (content matches): $dst"
    else
      rm "$dst"
      if [[ "$MODE" == "copy" ]]; then
        cp "$src" "$dst"
      else
        ln -s "$src" "$dst"
      fi
      say "  refreshed: $dst"
    fi
    return
  fi
  # Plain file with different content → SKIP-AND-WARN
  say "  ⚠️  skipped (yours differs from ours): $dst"
  say "      Your version preserved. To use ours, remove yours and re-run."
}

# --- install CLAUDE.md per mode ---

install_claude_md_merge() {
  local target="$TARGET_DIR/CLAUDE.md"
  local our_source="$REPO_DIR/CLAUDE.md"

  # If our markers already exist in the target → in-place replace
  if [[ -f "$target" ]] && grep -qF "$BEGIN_MARKER" "$target" 2>/dev/null; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would update managed section in: $target"
      say "             (markers already present — replacing content between them)"
      return
    fi
    # Use awk + getline to splice content from our_source between markers.
    # This avoids the multiline-variable issue with awk's -v flag.
    local tmp
    tmp="$(mktemp)"
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v src="$our_source" '
      BEGIN { in_section = 0 }
      $0 == begin {
        in_section = 1
        print begin
        while ((getline line < src) > 0) print line
        close(src)
        print end
        next
      }
      $0 == end {
        in_section = 0
        next
      }
      in_section == 0 { print }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
    say "  updated managed section in: $target"
    return
  fi

  # No markers yet — fresh install or append to existing.
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would create $target with managed section"
      return
    fi
    {
      echo "$BEGIN_MARKER"
      cat "$our_source"
      echo "$END_MARKER"
    } > "$target"
    say "  created (new file): $target"
    return
  fi

  # Existing CLAUDE.md, no markers — append.
  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would append managed section to: $target"
    say "             (your existing content preserved above markers)"
    return
  fi
  {
    echo ""
    echo "$BEGIN_MARKER"
    cat "$our_source"
    echo "$END_MARKER"
  } >> "$target"
  say "  appended managed section to: $target"
}

install_claude_md_symlink_or_copy() {
  local src="$REPO_DIR/CLAUDE.md"
  local dst="$TARGET_DIR/CLAUDE.md"

  # Existing CLAUDE.md that's NOT a symlink to our repo and NOT identical →
  # diff check + halt unless --force (idea: protect user content)
  if [[ -f "$dst" && ! -L "$dst" ]]; then
    if ! diff -q "$dst" "$src" >/dev/null 2>&1; then
      local lines_diff
      lines_diff="$(diff "$dst" "$src" | grep -cE '^[<>]' || true)"
      say ""
      say "⚠️  Your existing CLAUDE.md differs from this repo's version."
      say "    Lines that differ: $lines_diff"
      say ""
      say "    In --$MODE mode, your file would be backed up and replaced."
      say "    Personal content above/below ours is NOT preserved in this mode."
      say "    Use --merge (default) if you want your content kept inline."
      say ""
      say "    Recommended next step:"
      say "      diff $dst $src | less"
      say ""
      if [[ "$FORCE" != "1" && "$DRY_RUN" != "1" ]]; then
        say "    To proceed anyway: re-run with --force"
        say "    To preview without changing anything: re-run with --dry-run"
        exit 2
      fi
    fi
  fi

  backup_if_exists "$dst"
  if [[ "$DRY_RUN" == "1" ]]; then
    [[ "$MODE" == "symlink" ]] && say "  [dry-run] would symlink: $dst -> $src" || say "  [dry-run] would copy: $src -> $dst"
    return
  fi
  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$src" "$dst"
    say "  symlinked: $dst -> $src"
  else
    cp "$src" "$dst"
    say "  copied:    $src -> $dst"
  fi
}

# --- merge notes (only for replace-mode backups with content diffs) ---
write_merge_notes() {
  [[ "$DRY_RUN" == "1" ]] && return
  [[ ! -d "$BACKUP_DIR" ]] && return

  local notes="$BACKUP_DIR/MERGE_NOTES.md"
  {
    echo "# Merge Notes"
    echo ""
    echo "Created by install.sh on $(date) — mode: --$MODE."
    echo ""
    echo "Files in this folder were moved here by install.sh because the repo's"
    echo "version replaced them. If your previous versions had personal or"
    echo "team-specific rules, merge them back into the live files (or move"
    echo "them to a project-level CLAUDE.md so they don't conflict with future"
    echo "repo updates)."
    echo ""
    echo "Once your config works, this backup folder is safe to delete:"
    echo "  rm -rf \"$BACKUP_DIR\""
  } > "$notes"
  say "  merge notes: $notes"
}

# --- main ---
say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "DRY-RUN — no changes will be made."
fi
say "Installing claude-customizations to $TARGET_DIR (mode: --$MODE)..."

mkdir -p "$TARGET_DIR/personas" 2>/dev/null || true

# CLAUDE.md — mode-specific
case "$MODE" in
  merge)             install_claude_md_merge ;;
  symlink|copy)      install_claude_md_symlink_or_copy ;;
esac

# personas/ — skip-and-warn across all modes
for persona in "$REPO_DIR/personas/"*.md; do
  install_with_skip_warn "$persona" "$TARGET_DIR/personas/$(basename "$persona")"
done

# Stop hook — skip-and-warn across all modes
install_with_skip_warn "$REPO_DIR/hooks/phase3-spawn-audit.py" "$TARGET_DIR/phase3-spawn-audit.py"
if [[ "$DRY_RUN" != "1" && -f "$TARGET_DIR/phase3-spawn-audit.py" ]]; then
  chmod +x "$TARGET_DIR/phase3-spawn-audit.py" 2>/dev/null || true
fi

# Merge notes if any backups happened
[[ -d "$BACKUP_DIR" ]] && write_merge_notes

say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "Dry-run complete. No changes made. Re-run without --dry-run to install."
else
  say "Done. Next steps:"
  say "  1. Wire the Stop hook into your settings.json (see README.md → 'Settings.json setup')"
  say "  2. Restart Claude Code to pick up new config"
  if [[ -d "$BACKUP_DIR" ]]; then
    say ""
    say "Backed-up originals: $BACKUP_DIR"
    [[ -f "$BACKUP_DIR/MERGE_NOTES.md" ]] && say "Read this first: $BACKUP_DIR/MERGE_NOTES.md"
  fi
  if [[ "$MODE" == "merge" ]]; then
    say ""
    say "Your CLAUDE.md was updated in --merge mode."
    say "To update to a newer repo version: 'git pull' then 're-run ./install.sh'."
  fi
fi
