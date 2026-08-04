# Aliases.
#
# Derived from measured shell history, not guesswork. Frequencies in comments
# are from the author's history at the time of writing.
#
# Deliberately NO git aliases: oh-my-zsh's git plugin already defines gst, gaa,
# gcmsg, gp, gd, glo, gco and gl. See the alias table in README.md.
#
# Parent-directory shortcuts (.. / ... / ....) are NOT defined here even though
# they're among the most-used commands in the author's history: 40-navigation.zsh
# already owns them (it loads before this module and has its own test coverage).
# Defining them again here would be a duplicate definition across two modules.

# --- modern replacements, each guarded ---------------------------------------
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --git --group-directories-first --icons=auto'
  alias tree='eza --tree --level=2 --icons=auto'
fi

command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never --style=plain'

# --- flutter (315 invocations) -----------------------------------------------
if command -v flutter >/dev/null 2>&1; then
  alias fr='flutter run'                      # 216
  alias fbi='flutter build ipa --release'     # 31
  alias fc='flutter clean'                    # 16
  alias fpg='flutter pub get'                 # 14
fi

# --- npm (201 invocations) ---------------------------------------------------
#
# Deliberately an if/fi, not `command -v npm ... && alias ...`: this is the
# last statement in the file, so its exit status becomes the exit status of
# `source 50-aliases.zsh` itself (same bug class zsh/zshrc:18-27 already
# warns about for its own trailing conditional). The && form is false
# whenever npm is merely absent, which would trip a caller's `set -e` and
# silently abort everything sourced after this module. Do not "simplify"
# this back to `&&` -- that reintroduces the abort.
if command -v npm >/dev/null 2>&1; then
  alias nrd='npm run dev'   # 182
fi
