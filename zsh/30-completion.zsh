# Completion system and fzf-tab.
#
# LOAD ORDER: after compinit (run below), and BEFORE zsh-autosuggestions
# (sourced in 60-prompt.zsh). fzf-tab must wrap the completion widget before
# autosuggestions wraps it, or completions silently fall back to the plain menu.

autoload -Uz compinit

# Rebuild the completion dump at most once a day; checking every start is slow.
if [[ -n "$HOME/.zcompdump"(#qN.mh+24) ]]; then
  compinit
else
  compinit -C          # trust the existing dump, skip security checks
fi

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
