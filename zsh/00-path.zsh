# PATH composition. Runs first so every later module can find binaries.
#
# Each entry is added only if the directory exists, so a fresh machine does not
# accumulate dangling PATH components.

# Homebrew prefix is resolved, never hardcoded: it differs between Apple Silicon
# (/opt/homebrew) and Intel (/usr/local).
if command -v brew >/dev/null 2>&1; then
  export BREW_PREFIX="$(brew --prefix)"
fi

# Later entries win, so these are listed least-specific first.
typeset -a _dotfiles_paths
_dotfiles_paths=(
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.npm-packages/bin"
)

# $BREW_PREFIX/bin last: the most specific of these entries, so it wins over
# the others when several exist, matching how Homebrew's own `shellenv`
# prepends it ahead of everything else. Guarded on BREW_PREFIX being set
# (only true when `brew` was found above) as well as the directory existing,
# same as every other entry here. Harmless on macOS in practice --
# /etc/zprofile's `brew shellenv` already puts this on PATH before zsh ever
# reaches this file -- but Spec 5.1 states it as a requirement of this
# module specifically, and this module should not silently depend on that
# separate mechanism to satisfy it.
[[ -n "${BREW_PREFIX:-}" ]] && _dotfiles_paths+=("$BREW_PREFIX/bin")

for _p in $_dotfiles_paths; do
  [[ -d "$_p" ]] && path=("$_p" $path)
done
unset _p _dotfiles_paths

# Drop duplicate PATH entries, keeping the first occurrence.
typeset -U path
