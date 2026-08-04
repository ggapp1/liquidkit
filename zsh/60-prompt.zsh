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
[[ -r "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh" ]] \
  && source "$DOTFILES_DIR/prompt/liquidprompt-transient.plugin.zsh"
