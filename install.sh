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
  # liquidprompt is not a `command`, it's a git clone, so it cannot go through
  # the OPTIONAL_TOOLS loop above. install_liquidprompt runs before this
  # function in the normal install path, so this only fires when that clone
  # never happened (offline first install) or genuinely failed -- exactly the
  # case that must never be silent: zsh/60-prompt.zsh no-ops without it, and
  # zsh falls all the way back to its plain, uncustomised default prompt with
  # no two-line layout and no transient collapse. No message, no theme, no hint.
  if [[ -d "$LIQUIDPROMPT_DIR/.git" ]]; then
    log "  found    liquidprompt"
  else
    log "  MISSING  liquidprompt - no prompt customisation at all: no two-line layout, no transient collapse; zsh falls back to its plain default prompt"
  fi
  log ""
  log "Install everything with: brew bundle --file=$DOTFILES_DIR/Brewfile"
}

LIQUIDPROMPT_TAG="v2.2.1"
LIQUIDPROMPT_DIR="$TARGET_HOME/.local/share/liquidprompt"

install_liquidprompt() {
  # Pinned to a tag: the transient plugin hooks powerline_full internals, so an
  # unpinned upstream change would break the prompt silently.
  if [[ -d "$LIQUIDPROMPT_DIR/.git" ]]; then
    log "  ok: liquidprompt already present"
    return 0
  fi
  log "  clone: liquidprompt $LIQUIDPROMPT_TAG"
  # Deliberately does not let a clone failure (e.g. no network on a first,
  # offline install) abort the whole installer via set -e: every other
  # dependency in this script degrades gracefully when absent, and this one
  # should too. `doctor`, called right after this in the install branch,
  # reports the miss plainly so it is never a silent gap.
  #
  # -c advice.detachedHead=false: v2.2.1 is an annotated tag, so a shallow
  # --branch checkout lands on it in detached HEAD state. Without this, git
  # prints its full "You are in 'detached HEAD' state..." essay on every
  # first install, which reads like something went wrong when nothing did.
  if ! act git -c advice.detachedHead=false clone --quiet --depth 1 \
      --branch "$LIQUIDPROMPT_TAG" \
      https://github.com/liquidprompt/liquidprompt.git "$LIQUIDPROMPT_DIR"; then
    log "  warn: liquidprompt clone failed (offline?) - retry later with:"
    log "        git clone --branch $LIQUIDPROMPT_TAG https://github.com/liquidprompt/liquidprompt.git $LIQUIDPROMPT_DIR"
  fi
  return 0
}

import_atuin_history() {
  # One-time migration of existing shell history into atuin's database.
  # Belongs here rather than in 20-history.zsh: that file runs on every shell
  # start, and importing repeatedly would be slow and pointless.
  command -v atuin >/dev/null 2>&1 || return 0

  # atuin stores its database under this directory; its presence means a prior
  # import already happened.
  local db="${XDG_DATA_HOME:-$TARGET_HOME/.local/share}/atuin/history.db"
  if [[ -e "$db" ]]; then
    log "  ok: atuin history already imported"
    return 0
  fi

  log "  import: existing shell history into atuin"
  # HOME is overridden for this invocation only: atuin resolves its own
  # config/data directories, and the shell history files it scans, from $HOME
  # -- not from $TARGET_HOME, which is purely this script's own bookkeeping
  # variable and nothing atuin has ever heard of. Without this override,
  # `DOTFILES_INSTALL_HOME=<tmp> ./install.sh` (exactly what every test in
  # tests/test_install.sh does) would still import into the REAL $HOME's
  # atuin database, silently mutating a developer's actual shell history on
  # every test run -- precisely what that file's own header comment promises
  # never happens. For a real install, TARGET_HOME already equals $HOME, so
  # this override changes nothing.
  act env HOME="$TARGET_HOME" atuin import auto \
    || log "  warn: atuin import failed; rerun manually with: atuin import auto"
  return 0
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
install_liquidprompt
import_atuin_history
(( DRY_RUN )) || doctor
log ""
log "Done. Restart your shell or run: exec zsh"
