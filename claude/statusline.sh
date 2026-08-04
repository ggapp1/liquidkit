#!/usr/bin/env bash
# Claude Code statusline. Reads the status JSON on stdin, prints one line.
#
# Register in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
#
# Every field is defaulted. A schema change should shorten this line, never
# break the TUI, so failures must stay silent and the exit status must be 0.
set +e

# Force the C locale for this process. Without it, bash's own printf(1)
# builtin parses/formats numbers per LC_NUMERIC -- under locales that use a
# comma decimal separator (e.g. pt_BR.UTF-8) it rejects a perfectly valid
# "1.23" as "invalid number", corrupting the cost segment. This must be a
# real assignment (not a per-command `LC_ALL=C printf ...` prefix): bash only
# re-runs setlocale() on an actual variable assignment, not on a builtin's
# temporary per-command environment.
LC_ALL=C

input="$(cat 2>/dev/null)"

# Without jq there is nothing to parse; emit a minimal line and stop.
if ! command -v jq >/dev/null 2>&1; then
  printf 'claude\n'
  exit 0
fi

field() {
  local val
  val="$(printf '%s' "$input" | jq -rc "$1 // empty" 2>/dev/null)"
  # Guard the single-line invariant against unexpected shapes: -c keeps a
  # non-scalar (object/array, from a schema change) on one line instead of
  # jq's default pretty-print, and stripping control characters guards
  # against a string value that itself embeds one (e.g. a crafted
  # display_name). This must strip the whole [:cntrl:] class, not just \n and
  # \r: \x0b (vertical tab) is not \n or \r but most terminals still treat it
  # as a line feed, so a val//$'\n'/ / val//$'\r'/ pair alone lets it straight
  # through -- breaking the single-line invariant on screen while `wc -l`
  # (which only counts \n) stays fooled into reporting one line. ANSI escapes
  # (ESC, e.g. cursor-up/clear-line sequences) and \b are control characters
  # too and are caught by the same substitution.
  val="${val//[[:cntrl:]]/ }"
  printf '%s' "$val"
}

# --- colour ------------------------------------------------------------------
# Basic ANSI (30-37), NOT 256-colour, and deliberately so. This is the opposite
# of the choice in prompt/liquidpromptrc, for the opposite reason: there we own
# the segment background, so a fixed 256-colour foreground is predictable. Here
# Claude Code's TUI owns the background and ships light and dark themes, so a
# fixed colour that reads well on one can vanish on the other. Basic ANSI maps
# through the user's own terminal palette, so it adapts with their theme.
#
# No background colours and no bold for the same reason - see the same file's
# note on terminals that brighten bold text.
if [[ -n "${NO_COLOR:-}" ]]; then          # https://no-color.org
  c_model='' c_dir='' c_branch='' c_add='' c_del='' c_warn='' c_sep='' c_off=''
else
  c_model=$'\e[36m'    # cyan
  c_dir=$'\e[34m'      # blue
  c_branch=$'\e[32m'   # green
  c_add=$'\e[32m'      # green
  c_del=$'\e[31m'      # red
  c_warn=$'\e[33m'     # yellow
  c_sep=$'\e[90m'      # bright black / grey
  c_off=$'\e[0m'
fi

# Cost segment is opt-out, so the repo keeps the feature while an individual can
# switch it off:  "command": "LIQUIDKIT_STATUSLINE_COST=0 ~/.claude/statusline.sh"
: "${LIQUIDKIT_STATUSLINE_COST:=1}"

model="$(field '.model.display_name')"
current_dir="$(field '.workspace.current_dir')"
cost="$(field '.cost.total_cost_usd')"
added="$(field '.cost.total_lines_added')"
removed="$(field '.cost.total_lines_removed')"
exceeded="$(field '.exceeds_200k_tokens')"

parts=()

[[ -n "$model" ]] && parts+=("${c_model}${model}${c_off}")

if [[ -n "$current_dir" ]]; then
  # $HOME's basename is the username ("ggapp"), which says nothing about where
  # you are. Show the conventional ~ instead.
  if [[ "$current_dir" == "$HOME" ]]; then
    dir_name="~"
  else
    dir_name="$(basename "$current_dir" 2>/dev/null)"
  fi

  if [[ -n "$dir_name" ]]; then
    branch=""
    # Append the branch only when the directory really is a git work tree.
    if command -v git >/dev/null 2>&1 \
       && git -C "$current_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      branch="$(git -C "$current_dir" branch --show-current 2>/dev/null)"
    fi

    # Git worktrees are conventionally named after their branch, so the pair
    # reads as a stutter: "differentiated-backlog feat/differentiated-backlog".
    # They are different strings but the same information. When the branch's
    # last path segment matches the directory, show only the branch: it carries
    # everything the directory did, plus the "feat/" prefix the directory lost.
    if [[ -n "$branch" && "${branch##*/}" == "$dir_name" ]]; then
      parts+=("${c_branch}${branch}${c_off}")
    elif [[ -n "$branch" ]]; then
      parts+=("${c_dir}${dir_name}${c_off} ${c_branch}${branch}${c_off}")
    else
      parts+=("${c_dir}${dir_name}${c_off}")
    fi
  fi
fi

if (( LIQUIDKIT_STATUSLINE_COST )) && [[ -n "$cost" && "$cost" != "null" ]]; then
  # Validate before formatting: bash's printf can write partial output (e.g.
  # "0.00") to stdout *and* return non-zero on an invalid number, so using
  # its exit status to gate a "||" fallback would concatenate both instead
  # of choosing one (e.g. "$0.00$free").
  if [[ "$cost" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    parts+=("$(printf '$%.2f' "$cost" 2>/dev/null)")
  else
    parts+=("\$$cost")
  fi
fi

if [[ -n "$added" || -n "$removed" ]]; then
  parts+=("${c_add}+${added:-0}${c_off}/${c_del}-${removed:-0}${c_off}")
fi

# The payload exposes only this boolean - there is no context-remaining figure.
[[ "$exceeded" == "true" ]] && parts+=("${c_warn}⚠ 200k${c_off}")

# Join with a separator, then emit exactly one line.
out=""
for part in "${parts[@]:-}"; do
  [[ -z "$part" ]] && continue
  [[ -n "$out" ]] && out+="${c_sep} | ${c_off}"
  out+="$part"
done

printf '%s\n' "${out:-claude}"
exit 0
