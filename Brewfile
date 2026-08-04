# Optional dependencies. Everything degrades gracefully when absent.
#   brew bundle --file=Brewfile
#
# `brew bundle` has been built into Homebrew itself since 4.4.x, so no tap is
# needed. Do NOT add `tap "homebrew/bundle"` back: that tap is deprecated
# (Homebrew's DEPRECATED_OFFICIAL_TAPS) and tapping it calls `odie`, which
# makes `brew bundle` exit 1 on the very first line and install nothing.

# NOTE: liquidprompt is deliberately NOT listed here. Homebrew ships 2.3.0,
# while install.sh clones 2.2.1 pinned to a tag because the transient plugin
# hooks powerline_full internals verified against that version. Installing both
# would put two copies on disk and reintroduce exactly the version drift the
# pin exists to prevent.

# Shell ergonomics
brew "atuin"                    # SQLite-backed history, owns Ctrl-R
brew "fzf"                      # fuzzy finder
brew "fzf-tab"                  # completion menus through fzf
brew "zoxide"                   # frecent directory jumping
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"

# Modern CLI replacements
brew "eza"                      # ls
brew "bat"                      # cat
brew "fd"                       # find
brew "ripgrep"                  # grep

# Statusline
brew "jq"

# Development
brew "shellcheck"               # CI lints install.sh and the test scripts

# Fonts - required for the powerline glyphs in the prompt
cask "font-meslo-lg-nerd-font"
