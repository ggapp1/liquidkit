# liquidprompt-transient - two-line and transient prompt support for liquidprompt.
#
# liquidprompt 2.2.1 offers neither. This plugin adds both without patching it.
# Self-contained by design: it depends on liquidprompt and nothing else in this
# repo, so it can be extracted into its own repository unchanged.
#
# Source AFTER liquidprompt itself.

# --- settings ----------------------------------------------------------------
: ${LPT_ENABLE_TWO_LINE:=1}
: ${LPT_ENABLE_TRANSIENT:=1}
: ${LPT_MARK:='%F{141}❯%f '}
: ${LPT_TRANSIENT_MARK:='%F{240}❯%f '}

# --- two-line ----------------------------------------------------------------
# liquidprompt assigns PS1 from __lp_set_prompt, registered in precmd_functions.
# Appending our hook after it means ours runs last and sees the finished bar.
#
# LP_PS1_POSTFIX is NOT usable here: the powerline theme renders it as a coloured
# section inside the bar (powerline.theme:338), so it cannot carry a newline.
if (( LPT_ENABLE_TWO_LINE )); then
  _lpt_second_line() {
    PS1+=$'\n'"$LPT_MARK"
  }
  precmd_functions+=(_lpt_second_line)
fi

# --- transient ---------------------------------------------------------------
# Once a command runs, its prompt collapses to a bare mark so scrollback stays
# readable. liquidprompt has no such feature.
#
# The mechanism is zle-line-init plus .recursive-edit, as used by starship.
# DO NOT replace this with `add-zle-hook-widget line-finish` - that approach was
# tried and does nothing at all, with no error to explain why.
if (( LPT_ENABLE_TRANSIENT )); then

  # Preserve any existing binding instead of clobbering another plugin's widget.
  if (( ${+widgets[zle-line-init]} )); then
    zle -A zle-line-init _lpt_saved_line_init
  fi

  _lpt_line_init() {
    emulate -L zsh

    # Only the outermost editing context; nested contexts must fall through
    # or .recursive-edit will nest indefinitely.
    [[ $CONTEXT == start ]] || return 0

    (( ${+widgets[_lpt_saved_line_init]} )) && zle _lpt_saved_line_init

    while true; do
      zle .recursive-edit
      local -i ret=$?
      # $'\4' is Ctrl-D. Without ignore_eof it means "exit the shell".
      [[ $ret == 0 && $KEYS == $'\4' ]] || break
      [[ -o ignore_eof ]] || exit 0
    done

    # Repaint the finished line with the collapsed prompt, then hand off.
    # PS1 is rebuilt by liquidprompt's precmd on the next cycle, so overwriting
    # it here is safe and needs no restore.
    PS1="$LPT_TRANSIENT_MARK"
    RPROMPT=''
    zle .reset-prompt

    if (( ret )); then
      zle .send-break      # interrupted: discard the line
    else
      zle .accept-line
    fi
    return ret
  }

  zle -N zle-line-init _lpt_line_init
fi
