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
  # jq's default pretty-print, and stripping newlines/CRs guards against a
  # string value that itself embeds one (e.g. a crafted display_name).
  val="${val//$'\n'/ }"
  val="${val//$'\r'/ }"
  printf '%s' "$val"
}

model="$(field '.model.display_name')"
current_dir="$(field '.workspace.current_dir')"
cost="$(field '.cost.total_cost_usd')"
added="$(field '.cost.total_lines_added')"
removed="$(field '.cost.total_lines_removed')"
exceeded="$(field '.exceeds_200k_tokens')"

parts=()

[[ -n "$model" ]] && parts+=("$model")

if [[ -n "$current_dir" ]]; then
  dir_label="$(basename "$current_dir" 2>/dev/null)"
  if [[ -n "$dir_label" ]]; then
    # Append the branch only when the directory really is a git work tree.
    if command -v git >/dev/null 2>&1 \
       && git -C "$current_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      branch="$(git -C "$current_dir" branch --show-current 2>/dev/null)"
      [[ -n "$branch" ]] && dir_label="$dir_label ($branch)"
    fi
    parts+=("$dir_label")
  fi
fi

if [[ -n "$cost" && "$cost" != "null" ]]; then
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
  parts+=("+${added:-0}/-${removed:-0}")
fi

# The payload exposes only this boolean - there is no context-remaining figure.
[[ "$exceeded" == "true" ]] && parts+=("⚠ 200k")

# Join with a separator, then emit exactly one line.
out=""
for part in "${parts[@]:-}"; do
  [[ -z "$part" ]] && continue
  [[ -n "$out" ]] && out+=" | "
  out+="$part"
done

printf '%s\n' "${out:-claude}"
exit 0
