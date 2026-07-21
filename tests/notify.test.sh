# Tests for scripts/notify.sh
. "$(dirname "$0")/lib.sh"

t_title "notify.sh: sends notification in herdr env"
FAKEHOME=$(make_fake_home)
OLD_PATH="$PATH"
export PATH="$FAKEHOME/bin:$PATH"
export HERDR_CALL_LOG="/tmp/herdr-notify-test-log.txt"
: > "$HERDR_CALL_LOG"

HERDR_ENV=1 HERDR_PANE_ID="notify-pane" sh "$(dirname "$0")/../scripts/notify.sh" "Test Title" "Test Body" > /dev/null 2>&1
if grep -q "notification show" "$HERDR_CALL_LOG" 2>/dev/null; then
  t_pass "notification sent"
else
  t_fail "notification not sent (log: $(cat "$HERDR_CALL_LOG"))"
fi

t_title "notify.sh: fails outside herdr env"
output=$(HERDR_ENV= sh "$(dirname "$0")/../scripts/notify.sh" 2>&1 || true)
if echo "$output" | grep -q "must run inside"; then
  t_pass "notify fails outside herdr"
else
  t_fail "notify should fail outside herdr (got: $output)"
fi

rm -rf "$FAKEHOME"
export PATH="$OLD_PATH"
unset HERDR_CALL_LOG
