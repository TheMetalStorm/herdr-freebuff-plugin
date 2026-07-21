#!/bin/sh
# Test runner for freebuff-herdr integration.
# Usage: sh tests/run.sh [test_name_pattern]

set -e

SCRIPT_DIR="$(dirname "$0")"
export HERDR_BIN_PATH="${SCRIPT_DIR}/fixtures/herdr-stub.sh"
export HERDR_ENV=1
export HERDR_PANE_ID="test-pane-1"
export HERDR_STUB_LAST=/tmp/herdr-stub-last.txt
export HERDR_CALL_LOG=/tmp/herdr-stub-call-log.txt

# Reset stub state
: > "$HERDR_CALL_LOG"
: > "$HERDR_STUB_LAST"

cd "$(dirname "$0")/.."

pattern="${1:-}"

for test_file in "$SCRIPT_DIR"/*.test.sh; do
  [ -f "$test_file" ] || continue
  name="$(basename "$test_file")"
  [ -z "$pattern" ] || printf '%s' "$name" | grep -q "$pattern" || continue

  echo "==========================================="
  printf 'RUNNING: %s\n' "$name"
  echo "==========================================="

  # Run test in a subshell with clean state
  (
    FAIL_COUNT=0 PASS_COUNT=0 TEST_COUNT=0
    : > "$HERDR_CALL_LOG"
    : > "$HERDR_STUB_LAST"
    . "$test_file"
    summary
  )
  echo ""
done

echo "==========================================="
echo "All tests completed."
echo "==========================================="
