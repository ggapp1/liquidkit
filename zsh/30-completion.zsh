# Completion system and fzf-tab.
#
# LOAD ORDER: after compinit (run below), and BEFORE zsh-autosuggestions
# (sourced in 60-prompt.zsh). fzf-tab must wrap the completion widget before
# autosuggestions wraps it, or completions silently fall back to the plain menu.

autoload -Uz compinit

# Rebuild the completion dump at most once a day; checking every start is slow.
#
# The `(#qN.mh+24)` glob qualifier is only parsed as a qualifier when
# EXTENDED_GLOB is set. It is not set by default, and nothing upstream of
# this module sets it either -- without it, `(#qN.mh+24)` is inert trailing
# text, the `[[ -n ... ]]` test is always true, and `compinit` (the slow,
# full path) runs unconditionally, defeating the freshness check silently.
# `emulate -L zsh; setopt EXTENDED_GLOB` scopes the option to this anonymous
# function only, so it does not leak into the interactive shell that sources
# this module.
#
# The nullglob qualifier (N) means a missing dump file makes the glob
# expression evaluate to empty, i.e. `[[ -n ... ]]` is FALSE -- so on its
# own, a missing dump would take the "trust it" branch rather than the full
# rebuild, which is backwards. The explicit `! -f` check below handles that
# case up front (short-circuiting before the glob qualifier ever runs), so
# "missing" is treated the same as "stale".
() {
  emulate -L zsh
  setopt EXTENDED_GLOB
  if [[ ! -f "$HOME/.zcompdump" || -n "$HOME/.zcompdump"(#qN.mh+24) ]]; then
    compinit            # dump missing, or older than 24h: full run, with security checks
  else
    compinit -C          # dump is fresh: trust it, skip the checks
  fi
}

zstyle ':completion:*' menu no                    # fzf-tab replaces the built-in menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '[%d]'

# Homebrew installs fzf-tab under opt/, and the file is fzf-tab.zsh - NOT
# share/fzf-tab/fzf-tab.plugin.zsh, which is the layout plugin managers use.
# Getting this wrong makes the guard below return silently and fzf-tab simply
# never loads, with no error to explain why.
_fzf_tab_plugin="${BREW_PREFIX:-}/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
[[ -n "${BREW_PREFIX:-}" && -r "$_fzf_tab_plugin" ]] || { unset _fzf_tab_plugin; return 0; }
source "$_fzf_tab_plugin"
unset _fzf_tab_plugin

zstyle ':fzf-tab:*' switch-group ',' '.'

# Context-specific previews. Each guarded: a missing tool means no preview,
# never a broken completion.
if command -v eza >/dev/null 2>&1; then
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --level=2 --colour=always $realpath'
  zstyle ':fzf-tab:complete:z:*'  fzf-preview 'eza --tree --level=2 --colour=always $realpath'
fi

if command -v bat >/dev/null 2>&1; then
  zstyle ':fzf-tab:complete:*:*' fzf-preview \
    '[[ -d $realpath ]] && ls -1 $realpath || bat --style=numbers --color=always --line-range :200 $realpath 2>/dev/null'
fi

if command -v git >/dev/null 2>&1; then
  zstyle ':fzf-tab:complete:git-(add|diff|restore|checkout):*' fzf-preview \
    'git diff --color=always -- $word'
  zstyle ':fzf-tab:complete:git-(switch|rebase|merge):*' fzf-preview \
    'git log --oneline --color=always -20 $word'
fi

zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview 'ps -f -p $word'
