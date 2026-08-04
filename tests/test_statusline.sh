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
