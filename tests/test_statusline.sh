#!/usr/bin/env bash
# Tests for the Claude Code statusline. Every case feeds JSON on stdin.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$REPO/claude/statusline.sh"

FULL_JSON='{
  "hook_event_name": "Status",
  "session_id": "abc123",
  "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
  "workspace": {"current_dir": "/tmp/demo", "project_dir": "/tmp/demo"},
  "output_style": {"name": "default"},
  "cost": {"total_cost_usd": 1.2345, "total_lines_added": 42, "total_lines_removed": 7},
  "exceeds_200k_tokens": false
}'

test_renders_model_name() {
  local out; out="$(echo "$FULL_JSON" | "$SL")"
  [[ "$out" == *"Opus 5"* ]] || { echo "  model name missing from: $out"; return 1; }
}

test_renders_directory_basename() {
  local out; out="$(echo "$FULL_JSON" | "$SL")"
  [[ "$out" == *"demo"* ]] || { echo "  directory missing from: $out"; return 1; }
}

test_renders_cost_to_two_decimals() {
  local out; out="$(echo "$FULL_JSON" | "$SL")"
  [[ "$out" == *"1.23"* ]] || { echo "  cost missing from: $out"; return 1; }
}

test_renders_line_counts() {
  local out; out="$(echo "$FULL_JSON" | "$SL")"
  [[ "$out" == *"42"* && "$out" == *"7"* ]] || {
    echo "  line counts missing from: $out"; return 1; }
}

test_shows_warning_when_context_exceeded() {
  local json; json="${FULL_JSON/\"exceeds_200k_tokens\": false/\"exceeds_200k_tokens\": true}"
  local out; out="$(echo "$json" | "$SL")"
  [[ "$out" == *"⚠"* ]] || { echo "  no warning indicator: $out"; return 1; }
}

test_no_warning_when_context_ok() {
  local out; out="$(echo "$FULL_JSON" | "$SL")"
  # A do-nothing stub also has no "⚠" in its (empty) output, so require real
  # content first -- otherwise this assertion can never catch a broken script.
  [[ -n "$out" ]] || { echo "  produced no output at all"; return 1; }
  [[ "$out" != *"⚠"* ]] || { echo "  spurious warning: $out"; return 1; }
}

test_survives_empty_json() {
  local out
  if ! out="$(echo '{}' | "$SL")"; then
    echo "  non-zero exit on empty JSON"; return 1
  fi
  [[ -n "$out" ]] || { echo "  produced no output at all"; return 1; }
}

test_survives_malformed_json() {
  # A do-nothing stub also exits 0 on malformed input, so an exit-code-only
  # check can never catch a broken script. Also require a real, one-line
  # fallback (the governing principle: degrade to a shorter line, never break).
  echo 'not json at all' | "$SL" >/dev/null 2>&1 || {
    echo "  non-zero exit on malformed input"; return 1; }
  local lines
  lines="$(echo 'not json at all' | "$SL" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$lines" == "1" ]] || {
    echo "  emitted $lines lines on malformed input, expected 1"; return 1; }
  local out; out="$(echo 'not json at all' | "$SL" 2>/dev/null)"
  [[ -n "$out" ]] || { echo "  produced no output on malformed input"; return 1; }
}

test_emits_exactly_one_line() {
  local lines; lines="$(echo "$FULL_JSON" | "$SL" | wc -l | tr -d ' ')"
  [[ "$lines" == "1" ]] || { echo "  emitted $lines lines, expected 1"; return 1; }
}

test_strips_all_control_characters_not_just_newline_and_cr() {
  # field() used to strip only \n and \r. \x0b (vertical tab) is neither, but
  # most terminals still render it as a line feed, so a crafted field value
  # embedding it broke the single-line invariant on screen while `wc -l`
  # (which only counts \n) stayed fooled into reporting one line -- an
  # invisible failure of the exact guarantee this file's own comments defend.
  # ANSI cursor/clear-line escapes and a bare backspace are included too,
  # since they are control characters as well and must be caught by the same
  # fix, not special-cased.
  #
  # Run under NO_COLOR: the script legitimately emits its own ANSI colour
  # escapes, which are control characters too. Without this, the assertion
  # below cannot tell "the script coloured its output" from "a crafted field
  # value smuggled an escape through", and fails on the former. NO_COLOR
  # strips ours, so anything left must have come from the payload -- which is
  # exactly what this test is about.
  local json
  json='{"model": {"display_name": "Opus\u000b5\u001b[5A\u001b[2K\bHACK"}}'
  local out; out="$(echo "$json" | NO_COLOR=1 "$SL")"
  local lines; lines="$(echo "$json" | NO_COLOR=1 "$SL" | wc -l | tr -d ' ')"
  [[ "$lines" == "1" ]] || {
    echo "  emitted $lines lines for input with a vertical tab and ANSI escapes, expected 1: $out"; return 1; }
  # Assert no raw control bytes survive in the output, not just that wc -l
  # (which is blind to everything except \n) reports 1.
  if printf '%s' "$out" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "  output still contains a raw control character: $(printf '%s' "$out" | od -c | head -3)"
    return 1
  fi
}

test_worktree_branch_does_not_stutter_against_dir_name() {
  # Git worktrees are conventionally named after their branch, so dir+branch
  # reads as a repeat: "differentiated-backlog feat/differentiated-backlog".
  # Different strings, same information. Show only the branch, which carries
  # everything the directory did plus the prefix the directory lost.
  local tmp; tmp="$(mktemp -d)"
  local wt="$tmp/differentiated-backlog"
  mkdir -p "$wt"
  ( cd "$wt" && git init -q && git commit -q --allow-empty -m x \
      && git checkout -q -b feat/differentiated-backlog ) >/dev/null 2>&1
  local out
  out="$(printf '{"workspace":{"current_dir":"%s"}}' "$wt" | NO_COLOR=1 "$SL")"
  rm -rf "$tmp"
  [[ "$out" != *"differentiated-backlog feat/"* ]] || {
    echo "  dir and branch stutter: $out"; return 1; }
  [[ "$out" == *"feat/differentiated-backlog"* ]] || {
    echo "  branch missing entirely: $out"; return 1; }
}

test_home_directory_shows_tilde_not_username() {
  # basename "$HOME" is the username, which says nothing about location.
  local out
  out="$(printf '{"workspace":{"current_dir":"%s"}}' "$HOME" | NO_COLOR=1 "$SL")"
  [[ "$out" == *"~"* ]] || { echo "  expected ~ for \$HOME, got: $out"; return 1; }
  [[ "$out" != *"$(basename "$HOME")"* ]] || {
    echo "  leaked the username instead of ~: $out"; return 1; }
}

test_cost_segment_can_be_switched_off() {
  local json='{"cost":{"total_cost_usd":1.2345}}'
  local on off
  on="$(echo "$json" | NO_COLOR=1 "$SL")"
  off="$(echo "$json" | NO_COLOR=1 LIQUIDKIT_STATUSLINE_COST=0 "$SL")"
  [[ "$on" == *"1.23"* ]] || { echo "  cost missing when enabled: $on"; return 1; }
  [[ "$off" != *"1.23"* ]] || { echo "  cost still shown when disabled: $off"; return 1; }
}

test_colour_is_emitted_and_no_color_suppresses_it() {
  local json='{"model":{"display_name":"Opus 5"}}'
  local coloured plain
  coloured="$(echo "$json" | "$SL")"
  plain="$(echo "$json" | NO_COLOR=1 "$SL")"
  [[ "$coloured" == *$'\e['* ]] || { echo "  no colour emitted: $coloured"; return 1; }
  [[ "$plain" != *$'\e['* ]] || { echo "  NO_COLOR not honoured: $plain"; return 1; }
  # Colour must not cost the single-line guarantee.
  [[ "$(echo "$json" | "$SL" | wc -l | tr -d ' ')" == "1" ]] || {
    echo "  coloured output was not one line"; return 1; }
}
