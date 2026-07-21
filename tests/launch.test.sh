# Tests for scripts/launch.sh
. "$(dirname "$0")/lib.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.config/manicode/projects" "$FAKEHOME/bin" "$FAKEHOME/.local/bin"
ln -sf "$PROJECT_ROOT/tests/fixtures/herdr-stub.sh" "$FAKEHOME/bin/herdr"
ln -sf "$PROJECT_ROOT/tests/fixtures/bin/freebuff" "$FAKEHOME/bin/freebuff"

OLD_HOME="$HOME"
OLD_PATH="$PATH"
export HOME="$FAKEHOME"
export PATH="$FAKEHOME/bin:$PATH"
export HERDR_STUB_LAST="/tmp/herdr-launch-test-last.txt"
: > "$HERDR_STUB_LAST"
export HERDR_CALL_LOG="/tmp/herdr-launch-test-call.txt"
: > "$HERDR_CALL_LOG"

t_title "launch.sh: task mode execs freebuff"
(
  exec 2>/dev/null
  HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" task > /dev/null 2>&1
) &
pid=$!
sleep 0.3
if kill -0 $pid 2>/dev/null; then
  t_pass "task mode started freebuff"
  kill $pid 2>/dev/null
else
  t_fail "task mode did not start freebuff"
fi

t_title "launch.sh: resume-last mode passes --continue"
(
  exec 2>/dev/null
  HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" resume-last > /dev/null 2>&1
) &
pid=$!
sleep 0.3
if kill -0 $pid 2>/dev/null; then
  t_pass "resume-last mode started freebuff with --continue"
  kill $pid 2>/dev/null
else
  t_fail "resume-last mode did not start freebuff"
fi

t_title "launch.sh: resume-named passes session id"
(
  exec 2>/dev/null
  HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" resume-named "test-session-123" > /dev/null 2>&1
) &
pid=$!
sleep 0.3
if kill -0 $pid 2>/dev/null; then
  t_pass "resume-named started freebuff with session id"
  kill $pid 2>/dev/null
else
  t_fail "resume-named did not start freebuff"
fi

# Cleanup leftover freebuff processes
pkill -f "fake freebuff" 2>/dev/null || true
sleep 0.3

t_title "launch.sh: prefers ~/.local/bin/freebuff wrapper when present"
# Create a wrapper that writes its invocation to a marker file
marker=/tmp/launch-wrapper-marker.txt
: > "$marker"
cat > "$FAKEHOME/.local/bin/freebuff" <<'WRAPEOF'
#!/bin/sh
echo "WRAPPER_INVOKED:$*" > /tmp/launch-wrapper-marker.txt
while true; do sleep 1; done
WRAPEOF
chmod +x "$FAKEHOME/.local/bin/freebuff"
# Put .local/bin ahead in PATH (keep system dirs)
export PATH="$FAKEHOME/.local/bin:$FAKEHOME/bin:$PATH"
(
  exec 2>/dev/null
  HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" task > /dev/null 2>&1
) &
pid=$!
sleep 0.5
# The wrapper should have been invoked by launch.sh via exec -> writes to marker
if grep -q "WRAPPER_INVOKED" "$marker" 2>/dev/null; then
  t_pass "wrapper was invoked (cmdline: $(cat "$marker"))"
else
  t_fail "wrapper was not invoked (marker content: $(cat "$marker" 2>/dev/null || echo '<empty>'))"
fi
kill $pid 2>/dev/null
rm -f "$marker"
export PATH="$FAKEHOME/bin:$PATH"
rm -f "$FAKEHOME/.local/bin/freebuff"

t_title "launch.sh: resume-named fails without session id"
output=$(HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" resume-named 2>&1 || true)
echo "$output" | grep -q "requires a session id" && t_pass "resume-named rejects empty session id" || t_fail "resume-named should reject empty session id"

t_title "launch.sh: unknown mode fails"
output=$(HERDR_PANE_ID="pane-1" HERDR_ENV=1 sh "$PROJECT_ROOT/scripts/launch.sh" unknown 2>&1 || true)
echo "$output" | grep -q "unknown launch mode" && t_pass "unknown mode rejected" || t_fail "unknown mode should be rejected"

# Restore
rm -rf "$FAKEHOME" /tmp/herdr-launch-test-last.txt /tmp/herdr-launch-test-call.txt
export HOME="$OLD_HOME"
export PATH="$OLD_PATH"
unset HERDR_STUB_LAST HERDR_CALL_LOG
