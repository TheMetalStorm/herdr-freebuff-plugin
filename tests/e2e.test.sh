# End-to-end test: fake freebuff + status-watcher + herdr-stub
. "$(dirname "$0")/lib.sh"

# Resolve absolute paths before any cd
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.config/manicode/projects/test-project/chats" "$FAKEHOME/bin"
ln -sf "$PROJECT_ROOT/tests/fixtures/herdr-stub.sh" "$FAKEHOME/bin/herdr"
ln -sf "$PROJECT_ROOT/tests/fixtures/bin/freebuff" "$FAKEHOME/bin/freebuff"

OLD_HOME="$HOME"
OLD_PWD="$PWD"
OLD_PATH="$PATH"
export HOME="$FAKEHOME"
export PATH="$FAKEHOME/bin:$PATH"
export HERDR_CALL_LOG="/tmp/herdr-e2e-call-log.txt"
: > "$HERDR_CALL_LOG"
export HERDR_STUB_LAST="/tmp/herdr-e2e-last.txt"
: > "$HERDR_STUB_LAST"

# Shared content file for the pane-stub: the e2e test updates this file
# per-phase to simulate different on-screen states. The watcher's stub
# reads from this file each time it runs `herdr pane read`.
E2E_PANE_CONTENT="/tmp/herdr-e2e-pane-content.txt"
export HERDR_STUB_CONTENT_FILE="$E2E_PANE_CONTENT"
: > "$E2E_PANE_CONTENT"

PROJECT_DIR="/tmp/test-project"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

CHATS_DIR="$FAKEHOME/.config/manicode/projects/test-project/chats"

# Start a fake "freebuff" to monitor (just a sleep loop)
(
  trap 'exit 0' TERM INT
  while true; do sleep 1; done
) &
FAKE_FB_PID=$!

WATCHER_SCRIPT="$PROJECT_ROOT/scripts/status-watcher.sh"

t_title "e2e: watcher starts and reports idle"
HERDR_ENV=1 HERDR_PANE_ID="e2e-pane" HERDR_BIN_PATH="$FAKEHOME/bin/herdr" \
  nohup sh "$WATCHER_SCRIPT" "$FAKE_FB_PID" "e2e-pane" \
  > /dev/null 2>&1 &
WATCHER_PID=$!
sleep 3

if grep -qF -- "--state idle" "$HERDR_CALL_LOG" 2>/dev/null; then
  t_pass "watcher reported idle on start"
else
  t_fail "watcher did not report idle (log: $(cat "$HERDR_CALL_LOG"))"
fi

t_title "e2e: watcher reports working when chat starts"
WORK_CHAT="$CHATS_DIR/2026-01-01T00-00-00.000Z"
make_fake_chat "$WORK_CHAT" "working"
sleep 3

if grep -qF -- "--state working" "$HERDR_CALL_LOG" 2>/dev/null; then
  t_pass "watcher reported working"
else
  t_fail "watcher did not report working (log: $(cat "$HERDR_CALL_LOG"))"
fi

t_title "e2e: watcher reports blocked when ask-user pending"
# Simulate the ask_user popup on screen (needed now that classify validates
# screen confirms popup before returning blocked with a stale-file fallback)
cat "$PROJECT_ROOT/tests/fixtures/pane-ask-user.txt" > "$E2E_PANE_CONTENT"
BLOCK_CHAT="$CHATS_DIR/2026-01-01T00-05-00.000Z"
make_fake_chat "$BLOCK_CHAT" "blocked"
sleep 3

if grep -qF -- "--state blocked" "$HERDR_CALL_LOG" 2>/dev/null; then
  t_pass "watcher reported blocked"
else
  t_fail "watcher did not report blocked (log: $(cat "$HERDR_CALL_LOG"))"
fi

t_title "e2e: watcher reports idle when turn completes"
DONE_CHAT="$CHATS_DIR/2026-01-01T00-10-00.000Z"
make_fake_chat "$DONE_CHAT" "done"
# Clear screen content — turn is done, no popup
: > "$E2E_PANE_CONTENT"
sleep 3

if grep -qF -- "--state idle" "$HERDR_CALL_LOG" 2>/dev/null; then
  t_pass "watcher reported idle (done)"
else
  t_fail "watcher did not report idle (log: $(cat "$HERDR_CALL_LOG"))"
fi

t_title "e2e: watcher exits when freebuff dies"
kill "$FAKE_FB_PID" 2>/dev/null
sleep 2
if kill -0 "$WATCHER_PID" 2>/dev/null; then
  t_fail "watcher still running after freebuff died"
  kill "$WATCHER_PID" 2>/dev/null
else
  t_pass "watcher exited after freebuff died"
fi

# Cleanup
rm -rf "$FAKEHOME" "$PROJECT_DIR"
rm -f /tmp/herdr-e2e-call-log.txt /tmp/herdr-e2e-last.txt /tmp/e2e-debug.log /tmp/herdr-e2e-pane-content.txt
export HOME="$OLD_HOME"
export PATH="$OLD_PATH"
cd "$OLD_PWD"
unset HERDR_CALL_LOG HERDR_STUB_LAST HERDR_STUB_CONTENT_FILE
