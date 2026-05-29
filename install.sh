#!/usr/bin/env bash
#
# install.sh — Wire claude-code-conductor into ~/.claude/
#
# This script ONLY makes copies. Nothing in ~/.claude/ depends on this
# repo's filesystem location, so moving or deleting the repo will not
# break your config. To pick up repo updates, re-run install.sh.
#
# Features (each installable independently):
#   tier                  Effort Routing Framework (Quick/Standard/Analytical/Deep)
#   interaction-rules     AskUserQuestion timing
#   tool-use-discipline   Bash batching rule (reduces chat clutter)
#   plan-mode             Plan Mode Standards (7 standards + 8 mandatory sections)
#   personas              AI Team / Persona Architecture (CLAUDE.md section + 15 persona files)
#   memory                Memory Discipline (cross-session learning)
#   hook                  Phase 3 spawn-audit Stop hook (deterministic backstop)
#
# Dependencies (auto-resolved):
#   personas → tier
#   hook     → personas → tier
#
# Modes (choose ONE; default is --merge):
#   --merge      Append selected features into your existing CLAUDE.md,
#                each wrapped in per-feature markers. Idempotent: re-runs
#                refresh existing sections in place. Sections you don't
#                select get removed from your file.
#
#   --copy       Replace your CLAUDE.md with the repo's full content.
#                Incompatible with partial --features selection (the whole
#                file is overwritten). Use --merge if you want subset control.
#
# Helper flags:
#   --features=LIST   Comma-separated feature list. Default = all.
#                     Example: --features=tier,memory
#   --dry-run         Show what would happen. Make no changes.
#   --force           Suppress halt-on-diff in --copy mode.

set -euo pipefail

# --- config ---
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${CLAUDE_HOME:-$HOME/.claude}"
MODE="merge"   # default
DRY_RUN=0
FORCE=0
FEATURES_ARG=""   # filled by --features=...
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$TARGET_DIR/.backup-$TIMESTAMP"

# Canonical feature order (controls section ordering in CLAUDE.md).
# 'hook' isn't a CLAUDE.md section; it's listed last as a marker-only entry.
ALL_FEATURES="tier interaction-rules tool-use-discipline plan-mode personas memory hook"

# Legacy single-marker (from pre-2026-05-28 installs). Migrated to per-feature markers.
LEGACY_BEGIN_MARKER="<!-- BEGIN claude-customizations managed section -->"
LEGACY_END_MARKER="<!-- END claude-customizations managed section -->"

# --- feature config (bash 3+ compatible via case statements) ---

# Returns the `## ...` section header for a feature, or empty if the feature
# has no CLAUDE.md content (e.g., 'hook' is script-only).
feature_section() {
  case "$1" in
    tier)                  echo "## Effort Routing Framework" ;;
    interaction-rules)     echo "## Interaction Rules" ;;
    tool-use-discipline)   echo "## Tool Use Discipline" ;;
    plan-mode)             echo "## Plan Mode Standards" ;;
    personas)              echo "## AI Team" ;;
    memory)                echo "## Memory Discipline" ;;
    *)                     echo "" ;;
  esac
}

# Returns the single dependency for a feature (or empty if none).
feature_dep() {
  case "$1" in
    personas) echo "tier" ;;
    hook)     echo "personas" ;;
    *)        echo "" ;;
  esac
}

# Returns a human-readable label for messages.
feature_label() {
  case "$1" in
    tier)                  echo "Effort Routing Framework" ;;
    interaction-rules)     echo "Interaction Rules" ;;
    tool-use-discipline)   echo "Tool Use Discipline (bash batching)" ;;
    plan-mode)             echo "Plan Mode Standards" ;;
    personas)              echo "AI Team / Persona Architecture" ;;
    memory)                echo "Memory Discipline" ;;
    hook)                  echo "Phase 3 Spawn-Audit Hook" ;;
    *)                     echo "$1" ;;
  esac
}

# Returns 0 if needle appears in a space-separated haystack.
contains_feature() {
  local needle="$1"
  local haystack=" $2 "
  [[ "$haystack" == *" $needle "* ]]
}

# Resolves a comma-separated feature request into a space-separated list
# that includes all transitive dependencies, ordered by ALL_FEATURES.
resolve_features() {
  local requested="$1"
  requested="${requested//,/ }"
  # special-case "all"
  if [[ "$requested" == "all" ]]; then
    echo "$ALL_FEATURES"
    return
  fi
  # Validate names + collect into resolved set
  local resolved=""
  for f in $requested; do
    if [[ -z "$(feature_label "$f")" ]] || ! contains_feature "$f" "$ALL_FEATURES"; then
      echo "ERROR: unknown feature: '$f'. Valid: $ALL_FEATURES" >&2
      exit 1
    fi
    contains_feature "$f" "$resolved" || resolved="$resolved $f"
  done
  # Pull in deps until stable
  local changed=1
  while [[ "$changed" == "1" ]]; do
    changed=0
    for f in $resolved; do
      local dep
      dep="$(feature_dep "$f")"
      if [[ -n "$dep" ]] && ! contains_feature "$dep" "$resolved"; then
        resolved="$resolved $dep"
        changed=1
      fi
    done
  done
  # Re-order to canonical ALL_FEATURES order
  local ordered=""
  for f in $ALL_FEATURES; do
    if contains_feature "$f" "$resolved"; then
      ordered="$ordered $f"
    fi
  done
  echo "${ordered# }"
}

# --- args ---
for arg in "$@"; do
  case "$arg" in
    --merge)         MODE="merge" ;;
    --copy)          MODE="copy" ;;
    --features=*)    FEATURES_ARG="${arg#--features=}" ;;
    --dry-run)       DRY_RUN=1 ;;
    --force)         FORCE=1 ;;
    --help|-h)
      cat <<EOF
Usage: install.sh [--merge|--copy] [--features=LIST] [--dry-run] [--force]

This script only makes copies. Nothing in ~/.claude/ depends on the
repo's filesystem location. Re-run install.sh after 'git pull' to update.

Features (auto-resolves dependencies):
  tier                  Effort Routing Framework
  interaction-rules     AskUserQuestion timing
  tool-use-discipline   Bash batching rule (reduces chat clutter)
  plan-mode             Plan Mode Standards
  personas              AI Team / Persona Architecture (needs: tier)
  memory                Memory Discipline
  hook                  Phase 3 Spawn-Audit Hook (needs: personas, tier)

  --features=LIST    Comma-separated. Default: all
                     Examples:
                       --features=tier,memory
                       --features=plan-mode
                       --features=hook        (auto-pulls personas + tier)

Modes:
  --merge      (DEFAULT) Per-feature install. Each selected feature gets
               its own marker block in your CLAUDE.md. Features you DON'T
               select are removed from your file (idempotent set-management).
               Your personal content outside the markers is preserved.

  --copy       Replace your CLAUDE.md with the repo's full content.
               Requires --features=all (or omit --features). Existing
               CLAUDE.md is backed up.

Helper flags:
  --dry-run    Show what would happen. Make no changes. Always safe.
  --force      In --copy mode only: proceed even if existing CLAUDE.md
               differs from the repo's.

Persona files / hook script:
  - 'personas' feature installs 15 persona files into ~/.claude/personas/.
  - 'hook' feature installs ~/.claude/phase3-spawn-audit.py.
  - Skip-and-warn: if a target file exists with different content, your
    version is preserved.

Replaced files go to ~/.claude/.backup-<timestamp>/ with a MERGE_NOTES.md.

settings.json is NOT installed — see README.md.
EOF
      exit 0 ;;
    *) echo "Unknown arg: $arg (try --help)" >&2; exit 1 ;;
  esac
done

# Resolve features (default = all)
if [[ -z "$FEATURES_ARG" ]]; then
  FEATURES="$ALL_FEATURES"
else
  FEATURES="$(resolve_features "$FEATURES_ARG")"
fi

# --copy + partial features is incompatible
if [[ "$MODE" == "copy" && "$FEATURES" != "$ALL_FEATURES" ]]; then
  echo "ERROR: --copy mode requires all features (it overwrites the whole CLAUDE.md)." >&2
  echo "       Either drop --copy (use default --merge) or omit --features." >&2
  exit 1
fi

# --- guard ---
if [[ ! -d "$REPO_DIR/personas" ]] || [[ ! -f "$REPO_DIR/CLAUDE.md" ]]; then
  echo "ERROR: this script must run from the claude-code-conductor repo root." >&2
  echo "       Current REPO_DIR=$REPO_DIR" >&2
  exit 1
fi

# --- helpers ---
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

install_with_skip_warn() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would copy: $src -> $dst"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      say "  copied:    $dst"
    fi
    return
  fi
  if symlinks_into_repo "$dst"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would convert legacy symlink to copy: $dst"
    else
      rm "$dst"
      cp "$src" "$dst"
      say "  converted legacy symlink to copy: $dst"
    fi
    return
  fi
  if [[ -f "$dst" ]] && diff -q "$dst" "$src" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would refresh (content matches): $dst"
    else
      rm "$dst"
      cp "$src" "$dst"
      say "  refreshed: $dst"
    fi
    return
  fi
  say "  ⚠️  skipped (yours differs from ours): $dst"
  say "      Your version preserved. To use ours, remove yours and re-run."
}

# --- feature section management ---

feature_begin_marker() { echo "<!-- BEGIN claude-code-conductor:$1 -->"; }
feature_end_marker()   { echo "<!-- END claude-code-conductor:$1 -->"; }

# Extract a feature's section content from the repo's CLAUDE.md
extract_feature_content() {
  local feature="$1"
  local hdr
  hdr="$(feature_section "$feature")"
  [[ -z "$hdr" ]] && return
  awk -v hdr="$hdr" '
    BEGIN { in_section = 0 }
    $0 == hdr { in_section = 1; print; next }
    /^## [^#]/ && $0 != hdr { in_section = 0 }
    in_section { print }
  ' "$REPO_DIR/CLAUDE.md"
}

# Migrate legacy single-marker install to per-feature markers.
# Strips the legacy section; per-feature install will re-add as separate sections.
migrate_legacy_markers() {
  local target="$TARGET_DIR/CLAUDE.md"
  [[ ! -f "$target" ]] && return
  if ! grep -qF "$LEGACY_BEGIN_MARKER" "$target" 2>/dev/null; then return; fi
  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would migrate legacy single-marker install to per-feature markers"
    return
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$LEGACY_BEGIN_MARKER" -v end="$LEGACY_END_MARKER" '
    BEGIN { in_section = 0 }
    $0 == begin { in_section = 1; next }
    $0 == end   { in_section = 0; next }
    in_section == 0 { print }
  ' "$target" > "$tmp"
  mv "$tmp" "$target"
  say "  migrated: stripped legacy single managed section (will be replaced by per-feature sections)"
}

# Install/refresh a single feature's section in target CLAUDE.md
install_feature_section() {
  local feature="$1"
  local target="$TARGET_DIR/CLAUDE.md"
  local begin end
  begin="$(feature_begin_marker "$feature")"
  end="$(feature_end_marker "$feature")"

  local content_file
  content_file="$(mktemp)"
  extract_feature_content "$feature" > "$content_file"

  if [[ ! -s "$content_file" ]]; then
    rm -f "$content_file"
    return  # no CLAUDE.md content for this feature (e.g., 'hook')
  fi

  if [[ -f "$target" ]] && grep -qF "$begin" "$target" 2>/dev/null; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would refresh section: $feature"
      rm -f "$content_file"
      return
    fi
    local tmp
    tmp="$(mktemp)"
    awk -v begin="$begin" -v end="$end" -v src="$content_file" '
      BEGIN { in_section = 0 }
      $0 == begin {
        in_section = 1
        print begin
        while ((getline line < src) > 0) print line
        close(src)
        print end
        next
      }
      $0 == end { in_section = 0; next }
      in_section == 0 { print }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
    rm -f "$content_file"
    say "  refreshed section: $feature"
    return
  fi

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would create $target with section: $feature"
      rm -f "$content_file"
      return
    fi
    {
      echo "$begin"
      cat "$content_file"
      echo "$end"
    } > "$target"
    rm -f "$content_file"
    say "  created file + added section: $feature"
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would append section: $feature"
    rm -f "$content_file"
    return
  fi
  {
    echo ""
    echo "$begin"
    cat "$content_file"
    echo "$end"
  } >> "$target"
  rm -f "$content_file"
  say "  appended section: $feature"
}

# Remove a feature's section (and its markers) from target CLAUDE.md.
remove_feature_section() {
  local feature="$1"
  local target="$TARGET_DIR/CLAUDE.md"
  [[ ! -f "$target" ]] && return
  local begin end
  begin="$(feature_begin_marker "$feature")"
  end="$(feature_end_marker "$feature")"
  if ! grep -qF "$begin" "$target" 2>/dev/null; then return; fi
  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would remove section: $feature"
    return
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$begin" -v end="$end" '
    BEGIN { in_section = 0 }
    $0 == begin { in_section = 1; next }
    $0 == end   { in_section = 0; next }
    in_section == 0 { print }
  ' "$target" > "$tmp"
  mv "$tmp" "$target"
  say "  removed section: $feature"
}

# --- personas + hook helpers ---

install_personas() {
  for persona in "$REPO_DIR/personas/"*.md; do
    install_with_skip_warn "$persona" "$TARGET_DIR/personas/$(basename "$persona")"
  done
}

remove_personas() {
  [[ ! -d "$TARGET_DIR/personas" ]] && return
  for repo_persona in "$REPO_DIR/personas/"*.md; do
    local name target
    name="$(basename "$repo_persona")"
    target="$TARGET_DIR/personas/$name"
    if [[ ! -e "$target" && ! -L "$target" ]]; then continue; fi
    if symlinks_into_repo "$target"; then
      if [[ "$DRY_RUN" == "1" ]]; then
        say "  [dry-run] would remove legacy symlink: $target"
      else
        rm "$target"
        say "  removed legacy symlink: $target"
      fi
      continue
    fi
    if [[ -f "$target" ]] && diff -q "$target" "$repo_persona" >/dev/null 2>&1; then
      if [[ "$DRY_RUN" == "1" ]]; then
        say "  [dry-run] would remove persona: $target"
      else
        rm "$target"
        say "  removed persona: $target"
      fi
      continue
    fi
    say "  skipped (locally modified persona): $target"
  done
}

install_hook() {
  install_with_skip_warn "$REPO_DIR/hooks/phase3-spawn-audit.py" "$TARGET_DIR/phase3-spawn-audit.py"
  if [[ "$DRY_RUN" != "1" && -f "$TARGET_DIR/phase3-spawn-audit.py" ]]; then
    chmod +x "$TARGET_DIR/phase3-spawn-audit.py" 2>/dev/null || true
  fi
}

remove_hook() {
  local target="$TARGET_DIR/phase3-spawn-audit.py"
  if [[ ! -e "$target" && ! -L "$target" ]]; then return; fi
  if symlinks_into_repo "$target"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove legacy symlink hook: $target"
    else
      rm "$target"
      say "  removed legacy symlink hook: $target"
    fi
    return
  fi
  if [[ -f "$target" ]] && diff -q "$target" "$REPO_DIR/hooks/phase3-spawn-audit.py" >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would remove hook: $target"
    else
      rm "$target"
      say "  removed hook: $target"
    fi
    return
  fi
  say "  skipped (locally modified hook): $target"
}

# --- --copy mode (whole-file overwrite) ---

install_claude_md_copy() {
  local src="$REPO_DIR/CLAUDE.md"
  local dst="$TARGET_DIR/CLAUDE.md"

  if [[ -f "$dst" && ! -L "$dst" ]]; then
    if ! diff -q "$dst" "$src" >/dev/null 2>&1; then
      local lines_diff
      lines_diff="$(diff "$dst" "$src" | grep -cE '^[<>]' || true)"
      say ""
      say "⚠️  Your existing CLAUDE.md differs from this repo's version."
      say "    Lines that differ: $lines_diff"
      say ""
      say "    In --copy mode, your file would be backed up and replaced."
      say "    Use --merge (default) if you want personal content preserved."
      say ""
      say "    Recommended next step:"
      say "      diff $dst $src | less"
      say ""
      if [[ "$FORCE" != "1" && "$DRY_RUN" != "1" ]]; then
        say "    To proceed anyway: re-run with --force"
        exit 2
      fi
    fi
  fi

  if symlinks_into_repo "$dst"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      say "  [dry-run] would convert legacy symlink to copy: $dst"
    else
      rm "$dst"
      cp "$src" "$dst"
      say "  converted legacy symlink to copy: $dst"
    fi
    return
  fi

  backup_if_exists "$dst"
  if [[ "$DRY_RUN" == "1" ]]; then
    say "  [dry-run] would copy: $src -> $dst"
    return
  fi
  cp "$src" "$dst"
  say "  copied:    $src -> $dst"
}

# --- merge notes ---
write_merge_notes() {
  [[ "$DRY_RUN" == "1" ]] && return
  [[ ! -d "$BACKUP_DIR" ]] && return
  local notes="$BACKUP_DIR/MERGE_NOTES.md"
  {
    echo "# Merge Notes"
    echo ""
    echo "Created by install.sh on $(date) — mode: --$MODE, features: $FEATURES"
    echo ""
    echo "Files in this folder were moved here by install.sh. If your previous"
    echo "versions had personal or team-specific rules, merge them back into the"
    echo "live files (or move them to a project-level CLAUDE.md so they don't"
    echo "conflict with future repo updates)."
    echo ""
    echo "Once your config works, this backup folder is safe to delete:"
    echo "  rm -rf \"$BACKUP_DIR\""
  } > "$notes"
  say "  merge notes: $notes"
}

# --- main ---
say ""
[[ "$DRY_RUN" == "1" ]] && say "DRY-RUN — no changes will be made."
say "Installing claude-code-conductor to $TARGET_DIR (mode: --$MODE)..."
say "Features selected: $FEATURES"
say ""

mkdir -p "$TARGET_DIR/personas" 2>/dev/null || true

# Migrate legacy single-marker installs before per-feature processing
migrate_legacy_markers

case "$MODE" in
  merge)
    # Per-feature install: iterate ALL_FEATURES in canonical order.
    # Selected → install/refresh. Not selected → remove if present.
    for f in $ALL_FEATURES; do
      if contains_feature "$f" "$FEATURES"; then
        # SELECTED — install
        if [[ "$f" == "personas" ]]; then
          install_feature_section "$f"
          install_personas
        elif [[ "$f" == "hook" ]]; then
          install_hook
        else
          install_feature_section "$f"
        fi
      else
        # NOT SELECTED — remove if previously installed
        if [[ "$f" == "personas" ]]; then
          remove_feature_section "$f"
          remove_personas
        elif [[ "$f" == "hook" ]]; then
          remove_hook
        else
          remove_feature_section "$f"
        fi
      fi
    done
    ;;
  copy)
    # Whole-file overwrite, plus personas + hook (always all in --copy)
    install_claude_md_copy
    install_personas
    install_hook
    ;;
esac

[[ -d "$BACKUP_DIR" ]] && write_merge_notes

# --- final messages ---
say ""
if [[ "$DRY_RUN" == "1" ]]; then
  say "Dry-run complete. No changes made. Re-run without --dry-run to install."
else
  say "Done. Features installed: $FEATURES"
  say ""
  say "Next steps:"
  if contains_feature "hook" "$FEATURES"; then
    say "  1. Wire the Stop hook into your settings.json (see README.md → 'Settings.json setup')"
    say "  2. Restart Claude Code to pick up new config"
  else
    say "  1. Restart Claude Code to pick up new config"
  fi
  if [[ -d "$BACKUP_DIR" ]]; then
    say ""
    say "Backed-up originals: $BACKUP_DIR"
    [[ -f "$BACKUP_DIR/MERGE_NOTES.md" ]] && say "Read this first: $BACKUP_DIR/MERGE_NOTES.md"
  fi
  if [[ "$MODE" == "merge" ]]; then
    say ""
    say "To update later: 'git pull' then re-run ./install.sh"
    say "To change feature set: re-run with a different --features=... value"
  fi
fi
