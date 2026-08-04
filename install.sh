#!/usr/bin/env bash
# Installs the dotfiles by symlinking them into $HOME.
# Safe by default: every existing target is backed up before being replaced.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${DOTFILES_INSTALL_HOME:-$HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
MODE="install"

# "<repo-relative source>:<$HOME-relative target>"
LINKS=(
  "zsh/zshrc:.zshrc"
  "prompt/liquidpromptrc:.config/liquidpromptrc"
  "claude/statusline.sh:.claude/statusline.sh"
)

# Optional tools, each with what breaks without it. Reported by the doctor pass.
OPTIONAL_TOOLS=(
  "atuin:Ctrl-R history search falls back to fzf"
  "fzf:no fuzzy history, file, or directory pickers"
  "zoxide:no 'z' smart directory jumping"
  "eza:ls/ll/tree aliases fall back to coreutils"
  "bat:cat alias falls back to coreutils; no completion previews"
  "fd:fzf falls back to 'find'"
  "jq:Claude Code statusline is disabled"
  "git:version-control prompt segments are hidden"
)

usage() {
  cat <<EOF
Usage: install.sh [--dry-run] [--uninstall] [--help]

  --dry-run    Print every action without performing it.
  --uninstall  Remove installed symlinks and restore the newest backups.
  --help       Show this message.
EOF
}

log()  { printf '%s\n' "$*"; }
act()  { if (( DRY_RUN )); then log "  would: $*"; else "$@"; fi; }

link_one() {
  local src="$DOTFILES_DIR/$1" dst="$TARGET_HOME/$2"

  if [[ ! -e "$src" ]]; then
    log "  skip: $1 (not present in repo)"
    return 0
  fi

  # Already correct — do nothing, and above all do not create a spurious backup.
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    log "  ok: $2"
    return 0
  fi

  act mkdir -p "$(dirname "$dst")"

  if [[ -e "$dst" || -L "$dst" ]]; then
    log "  backup: $2 -> $2.bak-$STAMP"
    act mv "$dst" "$dst.bak-$STAMP"
  fi

  log "  link: $2 -> $1"
  act ln -s "$src" "$dst"
}

unlink_one() {
  local src="$DOTFILES_DIR/$1" dst="$TARGET_HOME/$2"

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    log "  remove: $2"
    act rm "$dst"
  fi

  # Restore the newest backup, if any. Sorted lexically; the timestamp format sorts
  # chronologically, so the last entry is the most recent.
  local newest
  newest="$(find "$TARGET_HOME" -maxdepth 2 -name "$(basename "$2").bak-*" 2>/dev/null \
            | sort | tail -1)"
  if [[ -n "$newest" ]]; then
    log "  restore: $(basename "$newest") -> $2"
    act mv "$newest" "$dst"
  fi
}

doctor() {
  log ""
  log "Optional tools:"
  local entry tool why
  for entry in "${OPTIONAL_TOOLS[@]}"; do
    tool="${entry%%:*}"; why="${entry#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
      log "  found    $tool"
    else
      log "  MISSING  $tool - $why"
    fi
  done
  log ""
  log "Install everything with: brew bundle --file=$DOTFILES_DIR/Brewfile"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) MODE="uninstall" ;;
    --help|-h)   usage; exit 0 ;;
    *)           log "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

log "dotfiles: $DOTFILES_DIR"
log "target:   $TARGET_HOME"
(( DRY_RUN )) && log "mode:     DRY RUN (nothing will be written)"
log ""

if [[ "$MODE" == "uninstall" ]]; then
  log "Uninstalling:"
  for entry in "${LINKS[@]}"; do unlink_one "${entry%%:*}" "${entry#*:}"; done
  log ""
  log "Done. Backups older than the restored one were left in place."
  exit 0
fi

log "Installing:"
for entry in "${LINKS[@]}"; do link_one "${entry%%:*}" "${entry#*:}"; done
(( DRY_RUN )) || doctor
log ""
log "Done. Restart your shell or run: exec zsh"
