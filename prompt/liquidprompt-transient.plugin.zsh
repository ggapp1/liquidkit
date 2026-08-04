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
