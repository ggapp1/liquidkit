#!/usr/bin/env bash
# Tests for install.sh. All runs are retargeted via DOTFILES_INSTALL_HOME
# so the real $HOME is never touched.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_dry_run_creates_nothing() {
  local tmp; tmp="$(mktemp -d)"
  local output; output="$(DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --dry-run 2>&1)"
  echo "$output" | grep -q "would: ln -s" || {
    echo "  dry-run output did not name a planned symlink action"; return 1; }
  local count; count="$(find "$tmp" -mindepth 1 | wc -l | tr -d ' ')"
  [[ "$count" == "0" ]] || { echo "  dry-run wrote $count entries"; return 1; }
  rm -rf "$tmp"
}

test_install_creates_symlink() {
  local tmp; tmp="$(mktemp -d)"
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || { echo "  .zshrc is not a symlink"; return 1; }
  [[ "$(readlink "$tmp/.zshrc")" == "$REPO/zsh/zshrc" ]] || {
    echo "  .zshrc points at $(readlink "$tmp/.zshrc")"; return 1; }
  rm -rf "$tmp"
}

test_backs_up_existing_file() {
  local tmp; tmp="$(mktemp -d)"
  echo "ORIGINAL CONTENT" > "$tmp/.zshrc"
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  local backup; backup="$(find "$tmp" -maxdepth 1 -name '.zshrc.bak-*' | head -1)"
  [[ -n "$backup" ]] || { echo "  no backup created"; return 1; }
  grep -q "ORIGINAL CONTENT" "$backup" || {
    echo "  backup lost the original content"; return 1; }
  rm -rf "$tmp"
}

test_is_idempotent() {
  local tmp; tmp="$(mktemp -d)"
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" && "$(readlink "$tmp/.zshrc")" == "$REPO/zsh/zshrc" ]] || {
    echo "  .zshrc is not correctly symlinked after two installs"; return 1; }
  # Re-running over our own correct symlink must not manufacture a backup.
  local backups; backups="$(find "$tmp" -maxdepth 1 -name '.zshrc.bak-*' | wc -l | tr -d ' ')"
  [[ "$backups" == "0" ]] || {
    echo "  second run created $backups backup(s); expected 0"; return 1; }
  rm -rf "$tmp"
}

test_uninstall_restores_backup() {
  local tmp; tmp="$(mktemp -d)"
  echo "ORIGINAL CONTENT" > "$tmp/.zshrc"
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc did not become a symlink after install"; return 1; }
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --uninstall >/dev/null 2>&1
  [[ ! -L "$tmp/.zshrc" ]] || { echo "  .zshrc is still a symlink"; return 1; }
  grep -q "ORIGINAL CONTENT" "$tmp/.zshrc" || {
    echo "  original content not restored"; return 1; }
  rm -rf "$tmp"
}

test_uninstall_removes_link_when_no_backup() {
  local tmp; tmp="$(mktemp -d)"
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" >/dev/null 2>&1
  [[ -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc did not become a symlink after install"; return 1; }
  DOTFILES_INSTALL_HOME="$tmp" "$REPO/install.sh" --uninstall >/dev/null 2>&1
  [[ ! -e "$tmp/.zshrc" && ! -L "$tmp/.zshrc" ]] || {
    echo "  .zshrc should be gone entirely"; return 1; }
  rm -rf "$tmp"
}
