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

for _p in $_dotfiles_paths; do
  [[ -d "$_p" ]] && path=("$_p" $path)
done
unset _p _dotfiles_paths

# Drop duplicate PATH entries, keeping the first occurrence.
typeset -U path
