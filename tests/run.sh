#!/usr/bin/env bash
# Test entrypoint. Discovers test_*.sh (bash, functions named test_*)
# and test_*.py (python, run directly), reports pass/fail, exits non-zero on failure.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0

run_shell_file() {
  local file="$1"
  # shellcheck disable=SC1090
  source "$file"
  local fn
  for fn in $(declare -F | awk '{print $3}' | grep '^test_' || true); do
    if output="$("$fn" 2>&1)"; then
      echo "  PASS $(basename "$file")::$fn"; pass=$((pass+1))
    else
      echo "  FAIL $(basename "$file")::$fn"; echo "$output"; fail=$((fail+1))
    fi
    unset -f "$fn"
  done
}

for f in "$TESTS_DIR"/test_*.sh; do
  [[ -e "$f" ]] || continue
  echo "== $(basename "$f")"
  run_shell_file "$f"
done

for f in "$TESTS_DIR"/test_*.py; do
  [[ -e "$f" ]] || continue
  echo "== $(basename "$f")"
  if output="$(python3 "$f" 2>&1)"; then
    echo "$output"; pass=$((pass+1))
  else
    echo "$output"; fail=$((fail+1))
  fi
done

echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
