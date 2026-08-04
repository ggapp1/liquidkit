#!/usr/bin/env bash
# Tests for zsh/zshrc — the module loader.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_loads_modules_in_numeric_order() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/zsh"
  cp "$REPO/zsh/zshrc" "$tmp/zsh/zshrc"

  # Deliberately created out of order to prove sorting, not directory order.
  echo 'print -r -- second >> "$ORDER_LOG"' > "$tmp/zsh/20-second.zsh"
  echo 'print -r -- first  >> "$ORDER_LOG"' > "$tmp/zsh/10-first.zsh"
  echo 'print -r -- third  >> "$ORDER_LOG"' > "$tmp/zsh/30-third.zsh"

  local log="$tmp/order.log"
  ORDER_LOG="$log" HOME="$tmp" zsh -c "source '$tmp/zsh/zshrc'"

  local got; got="$(tr '\n' ' ' < "$log" | sed 's/ *$//')"
  [[ "$got" == "first second third" ]] || {
    echo "  expected 'first second third', got '$got'"; return 1; }
  rm -rf "$tmp"
}

test_exports_dotfiles_dir() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/zsh"
  cp "$REPO/zsh/zshrc" "$tmp/zsh/zshrc"

  local got
  got="$(HOME="$tmp" zsh -c "source '$tmp/zsh/zshrc'; print -r -- \$DOTFILES_DIR")"
  # macOS /tmp is a symlink to /private/tmp; :A resolves it, so compare resolved paths.
  local want; want="$(cd "$tmp" && pwd -P)"
  [[ "$got" == "$want" ]] || { echo "  expected '$want', got '$got'"; return 1; }
  rm -rf "$tmp"
}

test_sources_zshrc_local_last() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/zsh"
  cp "$REPO/zsh/zshrc" "$tmp/zsh/zshrc"
  echo 'print -r -- module >> "$ORDER_LOG"' > "$tmp/zsh/10-mod.zsh"
  echo 'print -r -- local  >> "$ORDER_LOG"' > "$tmp/.zshrc.local"

  local log="$tmp/order.log"
  ORDER_LOG="$log" HOME="$tmp" zsh -c "source '$tmp/zsh/zshrc'"

  local got; got="$(tr '\n' ' ' < "$log" | sed 's/ *$//')"
  [[ "$got" == "module local" ]] || {
    echo "  expected 'module local', got '$got'"; return 1; }
  rm -rf "$tmp"
}

test_survives_empty_module_dir() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/zsh"
  cp "$REPO/zsh/zshrc" "$tmp/zsh/zshrc"
  # No modules at all. An unguarded glob would abort here.
  HOME="$tmp" zsh -c "source '$tmp/zsh/zshrc'" || {
    echo "  loader failed on empty module dir"; return 1; }
  rm -rf "$tmp"
}
