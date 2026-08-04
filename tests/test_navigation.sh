#!/usr/bin/env bash
# Tests for the project jumper.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_p_is_defined() {
  local out
  out="$(zsh -c "DOTFILES_DIR='$REPO'; source '$REPO/zsh/40-navigation.zsh'; print -r -- \${+functions[p]}")"
  [[ "$out" == "1" ]] || { echo "  function p is not defined"; return 1; }
}

test_p_jumps_to_single_exact_match() {
  # NOTE: this is named for what it actually exercises -- the single-match
  # branch, which `return`s before `p` ever consults fzf. It is NOT a test
  # of the no-fzf degradation path: fzf is installed on this machine (and
  # most dev machines), so a test that wants that path to genuinely run
  # must deny fzf itself, not just happen to avoid it because the query
  # only matches one directory. See
  # test_p_prints_candidates_without_fzf below for the real no-fzf test.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/saas/billing" "$tmp/webapps/landing"
  local out
  out="$(zsh -c "
    DOTFILES_DIR='$REPO'
    PROJECTS_DIR='$tmp'
    source '$REPO/zsh/40-navigation.zsh'
    p billing
    pwd -P
  ")"
  [[ "$out" == "$(cd "$tmp/saas/billing" && pwd -P)" ]] || {
    echo "  expected to land in saas/billing, got '$out'"; return 1; }
  rm -rf "$tmp"
}

test_p_prints_candidates_without_fzf() {
  # Simulate "fzf not installed" by narrowing PATH to a minimal set that
  # cannot contain it, rather than shadowing it with a shell function (a
  # shadowing function would make `command -v fzf` SUCCEED and route
  # through the fzf branch instead of the degradation path under test).
  # Two directories share no distinguishing query here, so `p` (no
  # argument) is ambiguous between both and must fall through to printing
  # candidates rather than jumping to either.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/saas/billing" "$tmp/webapps/landing"
  # NOTE: expected paths are the literal $tmp interpolation, NOT
  # `cd ... && pwd -P`. `p`'s candidate glob never `cd`s when just listing
  # (only the single-match/fzf branches do), so it never resolves
  # symlinks -- and on macOS, `mktemp -d` returns a path under
  # /var/folders/..., itself a symlink to /private/var/folders/.... Using
  # the resolved form here mismatched the raw, unresolved form `p` prints.
  local billing_real landing_real out status
  billing_real="$tmp/saas/billing"
  landing_real="$tmp/webapps/landing"
  out="$(PATH='/usr/bin:/bin' zsh -c "
    DOTFILES_DIR='$REPO'
    PROJECTS_DIR='$tmp'
    source '$REPO/zsh/40-navigation.zsh'
    p
    st=\$?
    print -r -- \"PWD_AFTER:\$(pwd -P)\"
    exit \$st
  ")"
  status=$?
  [[ "$out" == *"$billing_real"* ]] || {
    echo "  expected saas/billing listed among candidates, got '$out'"; return 1; }
  [[ "$out" == *"$landing_real"* ]] || {
    echo "  expected webapps/landing listed among candidates, got '$out'"; return 1; }
  # It must print, not jump: cwd after the call is still wherever the
  # subshell started (never one of the two project directories).
  [[ "$out" == *"PWD_AFTER:$billing_real"* || "$out" == *"PWD_AFTER:$landing_real"* ]] && {
    echo "  p jumped to a project instead of printing candidates: '$out'"; return 1; }
  [[ "$status" -eq 0 ]] || {
    echo "  expected p to return 0 when printing ambiguous candidates, got $status"; return 1; }
  rm -rf "$tmp"
}

test_p_reports_no_match() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "$tmp/saas/billing"
  local out status
  out="$(zsh -c "
    DOTFILES_DIR='$REPO'
    PROJECTS_DIR='$tmp'
    source '$REPO/zsh/40-navigation.zsh'
    p nonexistent 2>&1
    exit \$?
  ")"
  status=$?
  [[ "$out" == *"no match"* ]] || {
    echo "  expected a 'no match' message, got '$out'"; return 1; }
  # The message alone is a weak anchor (substring matching is easy to
  # satisfy by accident); pair it with the exit status so a stub that
  # prints the right words but still succeeds (or a bug that reports "no
  # match" while actually cd-ing somewhere) is caught too.
  [[ "$status" -ne 0 ]] || {
    echo "  expected p to return non-zero when there is no match, got 0"; return 1; }
  rm -rf "$tmp"
}

test_p_errors_when_projects_dir_missing() {
  local tmp; tmp="$(mktemp -d)"
  rmdir "$tmp"   # exists nowhere on disk, but the path itself is real and unique
  local out status
  out="$(zsh -c "
    DOTFILES_DIR='$REPO'
    PROJECTS_DIR='$tmp'
    source '$REPO/zsh/40-navigation.zsh'
    p 2>&1
    exit \$?
  ")"
  status=$?
  [[ "$out" == *"does not exist"* ]] || {
    echo "  expected a 'does not exist' message, got '$out'"; return 1; }
  [[ "$status" -ne 0 ]] || {
    echo "  expected p to return non-zero when PROJECTS_DIR is missing, got 0"; return 1; }
}

test_p_errors_when_projects_dir_empty() {
  local tmp; tmp="$(mktemp -d)"
  local out status
  out="$(zsh -c "
    DOTFILES_DIR='$REPO'
    PROJECTS_DIR='$tmp'
    source '$REPO/zsh/40-navigation.zsh'
    p 2>&1
    exit \$?
  ")"
  status=$?
  [[ "$out" == *"no projects"* ]] || {
    echo "  expected a 'no projects' message, got '$out'"; return 1; }
  [[ "$status" -ne 0 ]] || {
    echo "  expected p to return non-zero when PROJECTS_DIR is empty, got 0"; return 1; }
  rm -rf "$tmp"
}

test_parent_directory_aliases_are_defined() {
  local out
  out="$(zsh -c "DOTFILES_DIR='$REPO'; source '$REPO/zsh/40-navigation.zsh'; print -r -- \"\${aliases[..]}|\${aliases[...]}|\${aliases[....]}\"")"
  [[ "$out" == "cd ..|cd ../..|cd ../../.." ]] || {
    echo "  expected 'cd ..|cd ../..|cd ../../..', got '$out'"; return 1; }
}

test_navigation_sources_cleanly_without_zoxide() {
  # Simulate "zoxide not installed" by narrowing PATH to a minimal set that
  # cannot contain it, rather than shadowing it with a shell function (see
  # test_p_prints_candidates_without_fzf for why). zoxide is installed on
  # this machine, so without narrowing PATH this test would source with
  # zoxide present and never exercise the "absent" branch it is named for.
  #
  # NOTE: `zsh -c "set -e; ..."` sourcing cleanly is a weak signal here on
  # its own -- `eval "$(zoxide init zsh)"` run with NO guard at all still
  # sources cleanly (exit 0) when zoxide is absent, because a
  # missing-command failure inside a `$(...)` command substitution yields
  # empty stdout, and `eval ""` is a harmless no-op; it does not surface
  # as a failing simple command under `set -e`. The `z` function is also
  # correctly left undefined either way, guard or not, for the same
  # reason. What the guard actually buys is silence: without it, zsh
  # prints "command not found: zoxide" to stderr on every shell start.
  # Verified by deliberately removing the guard and confirming both of
  # these still hold true anyway -- only the stderr assertion below
  # catches that mutation.
  local out err
  out="$(PATH='/usr/bin:/bin' zsh -c "set -e; DOTFILES_DIR='$REPO'; source '$REPO/zsh/40-navigation.zsh'; print -r -- \${+functions[z]}")" \
    || { echo "  40-navigation.zsh errored without zoxide"; return 1; }
  err="$(PATH='/usr/bin:/bin' zsh -c "DOTFILES_DIR='$REPO'; source '$REPO/zsh/40-navigation.zsh'" 2>&1 1>/dev/null)"
  [[ "$out" == "0" ]] || {
    echo "  zoxide's 'z' function is defined even though zoxide is not on PATH"; return 1; }
  [[ -z "$err" ]] || {
    echo "  sourcing without zoxide printed to stderr (the guard should have skipped it): $err"; return 1; }
}

test_navigation_sources_cleanly_with_zoxide() {
  command -v zoxide >/dev/null 2>&1 || return 0   # nothing to assert without zoxide
  local out
  out="$(zsh -c "set -e; DOTFILES_DIR='$REPO'; source '$REPO/zsh/40-navigation.zsh'; print -r -- \${+functions[z]}")" \
    || { echo "  40-navigation.zsh errored with zoxide present"; return 1; }
  [[ "$out" == "1" ]] || {
    echo "  zoxide's 'z' function was not defined even though zoxide is on PATH"; return 1; }
}
