#!/usr/bin/env bash
#
# install.sh — Wire claude-customizations into ~/.claude/
#
# Default: symlinks files (so `git pull` propagates updates to your active config).
# Pass --copy to copy files instead (snapshot at install time).
#
# Safe re-run: existing files in ~/.claude/ are backed up to ~/.claude/.backup-<timestamp>/
# before being replaced.

set -euo pipefail

# --- config ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CLAUDE_HOME:-$HOME/.claude}"
MODE="symlink"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$TARGET_DIR/.backup-$TIMESTAMP"

# --- args ---
for arg in "$@"; do
  case "$arg" in
    --copy)   MODE="copy" ;;
    --help|-h)
      cat <<EOF
Usage: install.sh [--copy]

  (default)  Symlink files from this repo into ~/.claude/.
             Updates via 'git pull' propagate immediately.

  --copy     Copy files instead of symlinking.
             Independent snapshot; you must re-run install.sh to pick up updates.

Files installed:
  ~/.claude/CLAUDE.md
  ~/.claude/personas/<15 files>
  ~/.claude/phase3-spawn-audit.py   (the Stop hook)

Existing files are backed up to ~/.claude/.backup-<timestamp>/ before replacement.

settings.json is NOT installed automatically — see README.md for manual steps
(it contains user-specific data like API keys).
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

mkdir -p "$TARGET_DIR/personas"

# --- backup any existing files we're about to replace ---
backup_if_exists() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$BACKUP_DIR"
    local rel="${target#$TARGET_DIR/}"
    local backup_path="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$backup_path")"
    mv "$target" "$backup_path"
    echo "  backed up: $target -> $backup_path"
  fi
}

# --- install one file ---
install_file() {
  local src="$1"
  local dst="$2"
  backup_if_exists "$dst"
  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$src" "$dst"
    echo "  symlinked: $dst -> $src"
  else
    cp "$src" "$dst"
    echo "  copied:    $src -> $dst"
  fi
}

echo "Installing claude-customizations to $TARGET_DIR (mode: $MODE)..."

# CLAUDE.md
install_file "$REPO_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"

# personas/
for persona in "$REPO_DIR/personas/"*.md; do
  install_file "$persona" "$TARGET_DIR/personas/$(basename "$persona")"
done

# Stop hook script (sits at ~/.claude/ root, NOT inside hooks/ subdir)
# because some systems have hooks/ as root-owned (Claude Code installation artifact)
install_file "$REPO_DIR/hooks/phase3-spawn-audit.py" "$TARGET_DIR/phase3-spawn-audit.py"
chmod +x "$TARGET_DIR/phase3-spawn-audit.py" 2>/dev/null || true

echo
echo "Done. Next steps:"
echo "  1. Wire the Stop hook into your settings.json (see README.md → 'Settings.json setup')"
echo "  2. Restart Claude Code to pick up new CLAUDE.md and hook"
echo
if [[ -d "$BACKUP_DIR" ]]; then
  echo "Backed-up originals: $BACKUP_DIR"
fi
