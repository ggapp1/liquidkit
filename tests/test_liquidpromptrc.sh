#!/usr/bin/env bash
# Guards against the four bugs found in the original liquidpromptrc.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RC="$REPO/prompt/liquidpromptrc"

test_uses_real_battery_variable() {
  grep -q '^LP_ENABLE_BATT=0' "$RC" || {
    echo "  LP_ENABLE_BATT=0 not set"; return 1; }
  grep -q '^LP_ENABLE_BATTERY' "$RC" && {
    echo "  LP_ENABLE_BATTERY is not a real liquidprompt variable; use LP_ENABLE_BATT"
    return 1; }
  return 0
}

test_powerline_glyphs_are_not_empty() {
  # The original file had these as literal "" after the glyphs were stripped.
  local var
  for var in POWERLINE_HARD_DIVIDER POWERLINE_SOFT_DIVIDER POWERLINE_VCS_MARKER; do
    local line; line="$(grep "^$var=" "$RC" || true)"
    [[ -n "$line" ]] || { echo "  $var not defined"; return 1; }
    local value; value="$(echo "$line" | sed "s/^$var=//" | tr -d '"' | sed 's/[[:space:]]*#.*//')"
    [[ -n "$value" ]] || { echo "  $var is empty - glyph was stripped"; return 1; }
  done
  return 0
}

test_glyphs_are_private_use_area() {
  # U+E0B0 and friends live in the PUA. Confirms real glyphs, not placeholders.
  python3 - "$RC" <<'PY'
import sys
bad = []
for line in open(sys.argv[1], encoding="utf-8"):
    for var in ("POWERLINE_HARD_DIVIDER", "POWERLINE_SOFT_DIVIDER", "POWERLINE_VCS_MARKER"):
        if line.startswith(var + "="):
            value = line.split("=", 1)[1].split("#")[0].strip().strip('"')
            if not any(ord(c) >= 0xE000 for c in value):
                bad.append(f"{var} has no PUA glyph: {value!r}")
sys.exit("\n".join(bad) if bad else 0)
PY
}

test_clock_has_no_seconds() {
  # LP_TIME_ANALOG=0 alone does NOT remove seconds - it only selects the digital
  # clock. LP_TIME_FORMAT is what carries the format, and it defaults to
  # "%H:%M:%S". Assert on that variable specifically, and assert the value has
  # no seconds field, so this test cannot pass while the clock still shows them.
  local line; line="$(grep '^LP_TIME_FORMAT=' "$RC" || true)"
  [[ -n "$line" ]] || { echo "  LP_TIME_FORMAT not set; seconds default to on"; return 1; }
  local value; value="$(echo "$line" | sed 's/^LP_TIME_FORMAT=//' | tr -d '"')"
  [[ "$value" != *"%S"* ]] || {
    echo "  LP_TIME_FORMAT is '$value', which still includes seconds"; return 1; }
}

test_conda_base_is_suppressed() {
  grep -q 'LP_ENABLE_VIRTUALENV=1' "$RC" || {
    echo "  LP_ENABLE_VIRTUALENV=1 not set"; return 1; }
  grep -q 'CONDA_DEFAULT_ENV' "$RC" || {
    echo "  no rule suppressing the conda 'base' environment"; return 1; }
}
