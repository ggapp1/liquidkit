# oh-my-zsh bootstrap.
#
# ZSH_THEME is intentionally empty: the prompt comes from liquidprompt
# (see 60-prompt.zsh). Setting a theme here would draw a competing prompt.

export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
[[ -r "$ZSH/oh-my-zsh.sh" ]] || return 0   # not installed: no-op

ZSH_THEME=""

plugins=(
  git                    # gst, gaa, gcmsg, gp, gd, glo - see README alias table
  macos
  brew
  node
  npm
  flutter                # completions; 315 invocations in the author's history
  uv                     # completions; 50 invocations
  colored-man-pages
  command-not-found
)

source "$ZSH/oh-my-zsh.sh"
