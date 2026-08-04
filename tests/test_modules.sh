#!/usr/bin/env bash
# Tests that individual modules are safe to source in isolation.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source one module in a clean non-interactive zsh and return its exit status.
source_module() {
  local module="$1"; shift
  zsh -c "set -e; DOTFILES_DIR='$REPO'; source '$REPO/zsh/$module'; $*"
}

test_path_module_sources_cleanly() {
  source_module 00-path.zsh || { echo "  00-path.zsh failed to source"; return 1; }
}

test_path_module_exports_brew_prefix() {
  command -v brew >/dev/null 2>&1 || return 0   # nothing to assert without brew
  local got; got="$(source_module 00-path.zsh 'print -r -- $BREW_PREFIX')"
  [[ -n "$got" && -d "$got" ]] || {
    echo "  BREW_PREFIX was '$got', expected an existing directory"; return 1; }
}

test_path_module_adds_no_missing_dirs() {
  # Every PATH entry the module adds must actually exist.
  local out
  out="$(source_module 00-path.zsh 'for p in ${(s.:.)PATH}; do [[ -d $p ]] || print -r -- "MISSING:$p"; done')"
  [[ -z "$(echo "$out" | grep MISSING || true)" ]] || {
    echo "  PATH contains non-existent dirs:"; echo "$out"; return 1; }
}

test_ohmyzsh_module_sources_cleanly_without_omz() {
  # With ZSH pointing nowhere, the module must no-op rather than error.
  zsh -c "set -e; DOTFILES_DIR='$REPO'; ZSH=/nonexistent; source '$REPO/zsh/10-ohmyzsh.zsh'" \
    || { echo "  10-ohmyzsh.zsh errored when oh-my-zsh is absent"; return 1; }
}

test_no_hardcoded_home() {
  # Global constraint: the repo must never name one user's home directory.
  local hits
  hits="$(grep -rn '/Users/ggapp' "$REPO" --include='*.zsh' --include='*.sh' \
          --include='*.json' --include='*.md' 2>/dev/null | grep -v '^.*docs/' | grep -v '^.*\.superpowers/' | grep -v '^.*tests/' || true)"
  [[ -z "$hits" ]] || { echo "  hardcoded home found:"; echo "$hits"; return 1; }
}
