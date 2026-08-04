# History configuration.
#
# LOAD ORDER: must run AFTER 15-fzf.zsh so atuin's Ctrl-R binding wins.

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_IGNORE_ALL_DUPS    # a repeated command keeps only its newest entry
setopt HIST_REDUCE_BLANKS      # strip superfluous whitespace before saving
setopt HIST_IGNORE_SPACE       # a leading space keeps a command out of history
setopt HIST_VERIFY             # expand !! onto the line instead of running it blind
setopt EXTENDED_HISTORY        # record timestamp and duration
setopt SHARE_HISTORY           # concurrent shells see each other's history
setopt APPEND_HISTORY

command -v atuin >/dev/null 2>&1 || return 0

# --disable-up-arrow: atuin otherwise takes over Up, which surprises people who
# expect it to walk the previous commands in order. Ctrl-R is atuin's.
eval "$(atuin init zsh --disable-up-arrow)"
