# fzf key bindings and completion.
#
# LOAD ORDER: this must run BEFORE 20-history.zsh.
# fzf binds Ctrl-R, and so does atuin. Whichever initialises last wins.
# atuin is meant to win, so fzf goes first.
#
# Do NOT merge this into 30-completion.zsh. That file loads later, which would
# invert the ordering and silently hand Ctrl-R back to fzf.

command -v fzf >/dev/null 2>&1 || return 0

# Homebrew ships these under $(brew --prefix)/opt/fzf/shell.
if [[ -n "${BREW_PREFIX:-}" ]]; then
  [[ -r "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ]] \
    && source "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
  [[ -r "$BREW_PREFIX/opt/fzf/shell/completion.zsh" ]] \
    && source "$BREW_PREFIX/opt/fzf/shell/completion.zsh"
fi

# Prefer fd over find: faster, and it respects .gitignore.
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

command -v bat >/dev/null 2>&1 \
  && export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :200 {}'"

# Deliberately an if/fi, not `command -v eza ... && export ...`: this is the
# last statement in the file, so its exit status becomes the exit status of
# `source 15-fzf.zsh` itself (same bug class zsh/zshrc:18-27, 50-aliases.zsh:32-42
# already warn about for their own trailing conditionals). The && form is
# false whenever eza is merely absent, which would trip a caller's `set -e`
# and silently abort everything sourced after this module. Do not "simplify"
# this back to `&&` -- that reintroduces the abort.
if command -v eza >/dev/null 2>&1; then
  export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --colour=always {}'"
fi
