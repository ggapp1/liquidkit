#!/usr/bin/env bash
# Installs the dotfiles by symlinking them into $HOME.
# Safe by default: every existing target is backed up before being replaced.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${DOTFILES_INSTALL_HOME:-$HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
MODE="install"

# liquidprompt itself reads its config from
# ${XDG_CONFIG_HOME:-$HOME/.config}/liquidpromptrc (see
# ~/liquidprompt/liquidprompt's own resolution), not unconditionally from
# $HOME/.config. A hardcoded ".config/liquidpromptrc" target would land
# somewhere liquidprompt never looks whenever XDG_CONFIG_HOME is set, and the
# prompt would silently fall back to its defaults with no error. Falling back
# to $TARGET_HOME/.config (not $HOME/.config) keeps this correct under
# DOTFILES_INSTALL_HOME too.
CONFIG_HOME="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"

# "<repo-relative source>:<target>". The target is resolved relative to
# $TARGET_HOME unless it already starts with "/", in which case it is used
# as-is -- see link_one/unlink_one. liquidpromptrc uses the latter so it can
# honour $CONFIG_HOME above instead of being hardcoded under $TARGET_HOME.
LINKS=(
  "zsh/zshrc:.zshrc"
  "prompt/liquidpromptrc:$CONFIG_HOME/liquidpromptrc"
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
  local src="$DOTFILES_DIR/$1"
  local dst="$2"
  # $2 is $TARGET_HOME-relative by default; an entry that already starts
  # with "/" (liquidpromptrc, via $CONFIG_HOME above) is used as-is.
  [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"

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
  local src="$DOTFILES_DIR/$1"
  local dst="$2"
  [[ "$dst" == /* ]] || dst="$TARGET_HOME/$dst"
  local removed=0

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    log "  remove: $2"
    act rm "$dst"
    removed=1
  fi

  # Restore the newest backup, if any, searched in $dst's own directory --
  # the exact place link_one creates it (`mv "$dst" "$dst.bak-$STAMP"`, a
  # sibling of $dst) -- rather than a maxdepth-2 search rooted at
  # $TARGET_HOME. That rooting stopped being reliable once a target could be
  # an absolute path outside $TARGET_HOME entirely (liquidpromptrc, via
  # $CONFIG_HOME above, when $XDG_CONFIG_HOME points somewhere not nested
  # under $TARGET_HOME): a backup made there would sit deeper than, or
  # entirely outside, what a $TARGET_HOME-rooted maxdepth-2 search could ever
  # find, silently breaking --uninstall's restore for exactly the setups this
  # fix's XDG-honouring is for. Sorted lexically; the timestamp format sorts
  # chronologically, so the last entry is the most recent.
  local newest
  newest="$(find "$(dirname "$dst")" -maxdepth 1 -name "$(basename "$dst").bak-*" 2>/dev/null \
            | sort | tail -1)"
  if [[ -n "$newest" ]] && { (( removed )) || [[ ! -e "$dst" ]]; }; then
    log "  restore: $(basename "$newest") -> $2"
    act mv "$newest" "$dst"
  elif [[ -n "$newest" ]]; then
    log "  skip: $2 already exists and is not the symlink this repo manages; not overwriting it with $(basename "$newest")"
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
  # oh-my-zsh is not a `command` either (it's a framework sourced from a
  # directory, not a binary on $PATH) and this repo does not install it --
  # there is no supported non-interactive install path upstream, so it
  # cannot go through the OPTIONAL_TOOLS loop above, same reasoning that
  # gives liquidprompt its own dedicated check above. Without it,
  # zsh/10-ohmyzsh.zsh silently no-ops (its own :7 comment says so), and a
  # user loses every plugin in its plugins=(...) list -- including all eight
  # git aliases (gst, gaa, gcmsg, gp, gd, glo, gco, gl) the README's alias
  # table promises they "already have".
  if [[ -r "${ZSH:-$TARGET_HOME/.oh-my-zsh}/oh-my-zsh.sh" ]]; then
    log "  found    oh-my-zsh"
  else
    log "  MISSING  oh-my-zsh - no plugins at all: none of the eight git aliases (gst, gaa, gcmsg, gp, gd, glo, gco, gl), no flutter/npm/uv completions, no colored man pages, no macos/brew helpers - install with: sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
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
  # HOME, XDG_DATA_HOME and XDG_CONFIG_HOME are all overridden for this
  # invocation only: atuin resolves its own config/data directories, and the
  # shell history files it scans, from $HOME -- not from $TARGET_HOME, which
  # is purely this script's own bookkeeping variable and nothing atuin has
  # ever heard of. Without this override, `DOTFILES_INSTALL_HOME=<tmp>
  # ./install.sh` (exactly what every test in tests/test_install.sh does)
  # would still import into the REAL $HOME's atuin database, silently
  # mutating a developer's actual shell history on every test run --
  # precisely what that file's own header comment promises never happens.
  #
  # HOME alone is not enough: atuin resolves its data dir from $XDG_DATA_HOME
  # first and only falls back to $HOME/.local/share when that is unset (the
  # idempotency check just above already honours this, via
  # ${XDG_DATA_HOME:-$TARGET_HOME/.local/share}). A developer who has
  # XDG_DATA_HOME set in their real environment would otherwise still have
  # the real `atuin import auto` invoked against their real database here,
  # even under DOTFILES_INSTALL_HOME -- the exact regression this override
  # exists to prevent, just one environment variable further down atuin's own
  # resolution order. XDG_CONFIG_HOME is pinned alongside it for the same
  # reason: atuin also reads its config (and, in principle, could be pointed
  # at a different db path from there) from $XDG_CONFIG_HOME first. For a
  # real install, TARGET_HOME already equals $HOME and neither XDG variable
  # is being redirected away from its default, so this override changes
  # nothing.
  act env HOME="$TARGET_HOME" \
          XDG_DATA_HOME="$TARGET_HOME/.local/share" \
          XDG_CONFIG_HOME="$TARGET_HOME/.config" \
          atuin import auto \
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
