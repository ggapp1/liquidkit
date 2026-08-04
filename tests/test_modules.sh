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
  # Only the entries THIS module adds are its responsibility. The inherited
  # PATH routinely holds stale directories that are none of our business.
  local out
  out="$(zsh -c "
    DOTFILES_DIR='$REPO'
    typeset -A before
    for p in \${(s.:.)PATH}; do before[\$p]=1; done
    source '$REPO/zsh/00-path.zsh'
    for p in \${(s.:.)PATH}; do
      [[ -n \${before[\$p]-} ]] && continue
      [[ -d \$p ]] || print -r -- \"MISSING:\$p\"
    done
  ")"
  [[ -z "$out" ]] || { echo "  module added non-existent dirs:"; echo "$out"; return 1; }
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
          --include='*.json' --include='*.md' 2>/dev/null | grep -v '^.*docs/' | grep -v '^.*\.superpowers/' | grep -v '^.*test_modules\.sh:' || true)"
  [[ -z "$hits" ]] || { echo "  hardcoded home found:"; echo "$hits"; return 1; }
}

test_fzf_module_precedes_history_module() {
  # The Ctrl-R ordering constraint, asserted structurally so a future rename
  # or renumber trips the test rather than silently breaking atuin.
  local fzf_num hist_num
  fzf_num="$(basename "$REPO"/zsh/*-fzf.zsh | cut -d- -f1)"
  hist_num="$(basename "$REPO"/zsh/*-history.zsh | cut -d- -f1)"
  [[ "$fzf_num" -lt "$hist_num" ]] || {
    echo "  fzf module ($fzf_num) must load before history ($hist_num): both bind Ctrl-R"
    return 1; }
}

test_history_module_sets_options() {
  local out
  # NOTE: bare `setopt` prints option names with underscores stripped
  # (e.g. "histignorealldups"), so `grep -c hist_ignore_all_dups` against it
  # never matches regardless of whether the option is set. Use zsh's `-o`
  # option-test operator instead, which accepts the underscored form.
  #
  # NOTE: assertions are matched by an explicit sentinel prefix, not by line
  # position (head -1 / tail -1). On a machine with atuin installed,
  # `eval "$(atuin init zsh ...)"` may write extra lines to stdout, which
  # would shift positional output and make a line-indexed assertion misparse.
  out="$(source_module 20-history.zsh 'print -r -- "HISTSIZE=$HISTSIZE"; [[ -o hist_ignore_all_dups ]] && print -r -- "DUPS=1" || print -r -- "DUPS=0"')"
  local size; size="$(echo "$out" | grep '^HISTSIZE=' | cut -d= -f2)"
  [[ "$size" == "100000" ]] || { echo "  HISTSIZE was '$size', expected 100000"; return 1; }
  local dups; dups="$(echo "$out" | grep '^DUPS=' | cut -d= -f2)"
  [[ "$dups" == "1" ]] || { echo "  HIST_IGNORE_ALL_DUPS not set"; return 1; }
}

test_history_module_sources_cleanly_without_atuin() {
  # Simulate "atuin not installed" by narrowing PATH to a minimal set that
  # cannot contain it, rather than shadowing it with a shell function.
  # Shadowing made `command -v atuin` SUCCEED (a function is a valid
  # command), which skipped the module's guard entirely and routed through
  # `eval "$(atuin init ...)"` instead -- exercising neither the guard nor
  # the degradation path this test is named for. The module must degrade,
  # not error.
  PATH='/usr/bin:/bin' zsh -c "set -e; DOTFILES_DIR='$REPO'; source '$REPO/zsh/20-history.zsh'" \
    || { echo "  20-history.zsh errored without atuin"; return 1; }
}

test_prompt_module_sources_cleanly_without_liquidprompt() {
  # With LIQUIDPROMPT_DIR pointing nowhere, the module must no-op rather than
  # error. This is the module's only guard against `set -e` propagating a
  # failed `[[ ... ]]` test out of the sourcing shell -- a bare `return` here
  # (rather than `return 0`) would silently abort whatever sources it, the
  # exact bug class already found and fixed in the path/history/oh-my-zsh
  # modules. Run non-interactively (zsh -c) so the `$- == *i*` half of the
  # guard is false too, exercising the no-op path the same way a script
  # (rather than an interactive login shell) would hit it.
  zsh -c "set -e; DOTFILES_DIR='$REPO'; LIQUIDPROMPT_DIR=/nonexistent; source '$REPO/zsh/60-prompt.zsh'; echo REACHED_AFTER_SOURCE" \
    | grep -q '^REACHED_AFTER_SOURCE$' \
    || { echo "  60-prompt.zsh errored (or aborted the script) when liquidprompt is absent"; return 1; }
}

test_completion_module_sources_cleanly_without_fzf_tab() {
  zsh -c "set -e; DOTFILES_DIR='$REPO'; source '$REPO/zsh/30-completion.zsh'" \
    || { echo "  30-completion.zsh errored without fzf-tab"; return 1; }
}

test_completion_module_runs_compinit() {
  local out
  out="$(source_module 30-completion.zsh 'print -r -- ${+functions[compdef]}')"
  [[ "$out" == "1" ]] || { echo "  compinit did not run (compdef undefined)"; return 1; }
}
