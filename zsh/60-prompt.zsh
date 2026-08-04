# Prompt.
#
# LOAD ORDER: this must be the LAST module.
# zsh-syntax-highlighting wraps zle widgets and must be in place before the
# transient prompt binds zle-line-init.

# zsh-autosuggestions must precede zsh-syntax-highlighting; highlighting is last.
if [[ -n "${BREW_PREFIX:-}" ]]; then
  [[ -r "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
    && source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [[ -r "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
    && source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# liquidprompt is cloned by install.sh, pinned to a tag.
LIQUIDPROMPT_DIR="${LIQUIDPROMPT_DIR:-$HOME/.local/share/liquidprompt}"
[[ $- == *i* && -r "$LIQUIDPROMPT_DIR/liquidprompt" ]] || return 0
source "$LIQUIDPROMPT_DIR/liquidprompt"

# Two-line and transient behaviour. Must come after liquidprompt.
#
# Deliberately an if/fi, not `[[ -r ... ]] && source ...`: this is the last
# statement in the file, so its exit status becomes the exit status of
# `source 60-prompt.zsh` itself (same bug class zsh/zshrc:18-27,
# 50-aliases.zsh:32-42, and 15-fzf.zsh's eza guard already warn about for
# their own trailing conditionals). The && form is false whenever the
# transient plugin file is unreadable, which would trip a caller's `set -e`
# and silently abort everything sourced after this module. Do not "simplify"
# this back to `&&` -- that reintroduces the abort.
if [[ -r "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh" ]]; then
  source "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh"
fi
