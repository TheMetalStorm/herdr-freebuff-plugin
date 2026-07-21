# Tests for scripts/freebuff-wrapper.sh (the PATH wrapper installed by setup.sh)
. "$(dirname "$0")/lib.sh"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

t_title "wrapper: finds real freebuff and execs it"
FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.nvm/versions/node/v26.1.0/bin"
# Create a "real" freebuff that writes its args to a file for verification
real_log="$FAKEHOME/real-invocation.log"
cat > "$FAKEHOME/.nvm/versions/node/v26.1.0/bin/freebuff" <<'REALEOF'
#!/bin/sh
echo "$*" > /tmp/wrapper-test-real-args.txt
echo "REAL_FREEBUFF_EXECUTED" >&2
REALEOF
chmod +x "$FAKEHOME/.nvm/versions/node/v26.1.0/bin/freebuff"

# Install the wrapper with plugin root baked in (as setup.sh would do)
wrapper_path="$FAKEHOME/.local/bin/freebuff"
sed "s|__PLUGIN_ROOT__|${PROJECT_ROOT}|g" "$PROJECT_ROOT/scripts/freebuff-wrapper.sh" > "$wrapper_path"
chmod +x "$wrapper_path"

# PATH: .local/bin first (wrapper), then our fake real freebuff, then system paths
export PATH="$FAKEHOME/.local/bin:$FAKEHOME/.nvm/versions/node/v26.1.0/bin:$FAKEHOME/bin:$PATH"
OLD_HOME="$HOME"
export HOME="$FAKEHOME"
: > /tmp/wrapper-test-real-args.txt

# Invoke the wrapper directly (simulating "freebuff" on PATH)
output=$("$wrapper_path" --continue test-session 2>&1 || true)
t_is "REAL_FREEBUFF_EXECUTED" "$output" "wrapper execs real freebuff"
t_is "--continue test-session" "$(cat /tmp/wrapper-test-real-args.txt 2>/dev/null)" "real freebuff receives original args"

rm -rf "$FAKEHOME" /tmp/wrapper-test-real-args.txt
export HOME="$OLD_HOME"

t_title "wrapper: fails gracefully when no real freebuff on PATH"
FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.local/bin"
wrapper_path="$FAKEHOME/.local/bin/freebuff"
sed "s|__PLUGIN_ROOT__|${PROJECT_ROOT}|g" "$PROJECT_ROOT/scripts/freebuff-wrapper.sh" > "$wrapper_path"
chmod +x "$wrapper_path"
export PATH="$FAKEHOME/.local/bin:/bin:/usr/bin"
OLD_HOME="$HOME"
export HOME="$FAKEHOME"

output=$("$wrapper_path" 2>&1 || true)
echo "$output" | grep -q "real freebuff binary not found" && t_pass "wrapper reports error when binary missing" || t_fail "wrapper should report error (output: $output)"

rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"

t_title "wrapper: spawns watcher only in herdr env"
# Kill any stale watchers from prior tests
pkill -f "status-watcher.sh" 2>/dev/null || true
sleep 0.3
FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.nvm/versions/node/v26.1.0/bin"
# Real freebuff that sleeps (so wrapper execs it, stays alive for watcher check)
cat > "$FAKEHOME/.nvm/versions/node/v26.1.0/bin/freebuff" <<'REALEOF'
#!/bin/sh
echo "REAL_FREEBUFF_EXECUTED"
while true; do sleep 1; done
REALEOF
chmod +x "$FAKEHOME/.nvm/versions/node/v26.1.0/bin/freebuff"

wrapper_path="$FAKEHOME/.local/bin/freebuff"
sed "s|__PLUGIN_ROOT__|${PROJECT_ROOT}|g" "$PROJECT_ROOT/scripts/freebuff-wrapper.sh" > "$wrapper_path"
chmod +x "$wrapper_path"
export PATH="$FAKEHOME/.local/bin:$FAKEHOME/.nvm/versions/node/v26.1.0/bin:$PATH"
OLD_HOME="$HOME"
export HOME="$FAKEHOME"

# Without HERDR_ENV — should NOT spawn watcher
HERDR_ENV="" HERDR_PANE_ID="" "$wrapper_path" &
pid=$!
sleep 0.5
watcher_count=$(ps -ef | grep "status-watcher.sh" | grep -v grep | wc -l)
[ "$watcher_count" -eq 0 ] && t_pass "no watcher spawned outside herdr" || t_fail "watcher should not spawn outside herdr (count: $watcher_count)"
kill $pid 2>/dev/null

# With HERDR_ENV — SHOULD spawn watcher
HERDR_ENV=1 HERDR_PANE_ID="test-pane" "$wrapper_path" &
pid=$!
sleep 1
watcher_count=$(ps -ef | grep "status-watcher.sh.*test-pane" | grep -v grep | wc -l)
[ "$watcher_count" -ge 1 ] && t_pass "watcher spawned inside herdr" || t_fail "watcher should spawn inside herdr (count: $watcher_count)"
# Kill watchers and freebuff
pkill -f "status-watcher.sh.*test-pane" 2>/dev/null || true
kill $pid 2>/dev/null
pkill -f "status-watcher.sh.*test-pane" 2>/dev/null || true

rm -rf "$FAKEHOME"
export HOME="$OLD_HOME"
