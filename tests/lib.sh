#!/bin/sh
# Minimal test framework for freebuff-herdr integration.
# Usage: source lib.sh

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
CURRENT_TITLE=""

t_title() {
  CURRENT_TITLE="$1"
  TEST_COUNT=$((TEST_COUNT + 1))
  printf '\n=== TEST %d: %s ===\n' "$TEST_COUNT" "$1"
}

t_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '  PASS: %s\n' "$1"
}

t_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '  FAIL: %s\n' "$1"
}

t_ok() {
  if eval "$1"; then
    t_pass "$1"
  else
    t_fail "$1"
  fi
}

t_is() {
  expected="$1"
  actual="$2"
  msg="${3:-compare}"
  if [ "$actual" = "$expected" ]; then
    t_pass "$msg"
  else
    t_fail "$msg (expected: [$expected], got: [$actual])"
  fi
}

t_file_contains() {
  file="$1"
  pattern="$2"
  msg="${3:-file $1 contains $2}"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    t_pass "$msg"
  else
    t_fail "$msg (pattern not found in $1)"
  fi
}

summary() {
  printf '\n=== RESULTS ===\n'
  printf 'Tests: %d, Passed: %d, Failed: %d\n' "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT"
  [ "$FAIL_COUNT" -eq 0 ] && return 0 || return 1
}

# Create a temporary HOME for testing with fake freebuff config.
make_fake_home() {
  FAKEHOME=$(mktemp -d)
  mkdir -p "$FAKEHOME/.config/manicode/projects" "$FAKEHOME/bin"
  # Resolve absolute path to test fixtures (works even after cd)
  _tests_dir="$(cd "$(dirname "$0")" && pwd)"
  ln -sf "$_tests_dir/fixtures/herdr-stub.sh" "$FAKEHOME/bin/herdr"
  ln -sf "$_tests_dir/fixtures/bin/freebuff" "$FAKEHOME/bin/freebuff"
  printf '%s' "$FAKEHOME"
}

# Create a fake chat directory with state files.
# Arguments: chat_dir, variant ("blocked" | "working" | "done" | "idle")
make_fake_chat() {
  chat_dir="$1"
  variant="$2"
  mkdir -p "$chat_dir"

  case "$variant" in
    blocked-new)
      # AI message with tool/toolName=ask_user block (new freebuff format)
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[
  {"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"},
  {"id":"user-1","variant":"user","content":"ask me a question","blocks":[],"timestamp":"00:01 AM"},
  {"id":"ai-1","variant":"ai","content":"","blocks":[{"type":"text","content":"thinking"},{"type":"tool","toolName":"ask_user","toolCallId":"t1","input":{"questions":[{"question":"pick","header":"Pick","options":[{"label":"A","description":"desc"}]}]}}],"timestamp":"00:02 AM"}
]
JSONEOF
      rm -f "$chat_dir/log.jsonl"
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":3,"firstPrompt":"ask me a question","messagesSize":400,"messagesMtimeMs":1000}
JSONEOF
      ;;

    blocked)
      # AI message with ask-user block, no user reply after it
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[
  {"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"},
  {"id":"user-1","variant":"user","content":"hello","blocks":[],"timestamp":"00:01 AM"},
  {"id":"ai-1","variant":"ai","content":"thinking...","blocks":[{"type":"text","content":"thinking"}],"timestamp":"00:02 AM"},
  {"id":"ai-2","variant":"ai","content":"","blocks":[{"type":"text","content":"result"},{"type":"ask-user","toolCallId":"t1","questions":[{"question":"choose option","header":"pick","options":[{"label":"A","description":"desc"}]}]}],"timestamp":"00:03 AM"}
]
JSONEOF
      rm -f "$chat_dir/log.jsonl"
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":4,"firstPrompt":"hello","messagesSize":500,"messagesMtimeMs":1000}
JSONEOF
      ;;
    working)
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[
  {"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"},
  {"id":"user-1","variant":"user","content":"hello","blocks":[],"timestamp":"00:01 AM"},
  {"id":"ai-1","variant":"ai","content":"working...","blocks":[{"type":"text","content":"working"}],"timestamp":"00:02 AM"}
]
JSONEOF
      # Log has start but no finish
      cat > "$chat_dir/log.jsonl" <<'JSONEOF'
{"level":"INFO","timestamp":"2026-01-01T00:01:00.000Z","msg":"[send-message] Sending message"}
{"level":"INFO","timestamp":"2026-01-01T00:02:00.000Z","msg":"Start agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:05.000Z","msg":"End agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:10.000Z","msg":"Start agent test-agent step 2 (run1)"}
JSONEOF
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":3,"firstPrompt":"hello","messagesSize":300,"messagesMtimeMs":2000}
JSONEOF
      ;;
    done)
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[
  {"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"},
  {"id":"user-1","variant":"user","content":"hello","blocks":[],"timestamp":"00:01 AM"},
  {"id":"ai-1","variant":"ai","content":"","blocks":[{"type":"text","content":"done"}],"timestamp":"00:02 AM"}
]
JSONEOF
      cat > "$chat_dir/log.jsonl" <<'JSONEOF'
{"level":"INFO","timestamp":"2026-01-01T00:01:00.000Z","msg":"[send-message] Sending message"}
{"level":"INFO","timestamp":"2026-01-01T00:02:00.000Z","msg":"Start agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:05.000Z","msg":"End agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:10.000Z","msg":"Main prompt finished"}
JSONEOF
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":3,"firstPrompt":"hello","messagesSize":300,"messagesMtimeMs":3000}
JSONEOF
      ;;
    stale-blocked)
      # AI has ask-user but turn is finished (Main prompt finished after start).
      # classify should return "idle", not "blocked".
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[
  {"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"},
  {"id":"user-1","variant":"user","content":"hello","blocks":[],"timestamp":"00:01 AM"},
  {"id":"ai-1","variant":"ai","content":"","blocks":[{"type":"text","content":"result"},{"type":"ask-user","toolCallId":"t1","questions":[{"question":"choose option","header":"pick","options":[{"label":"A","description":"desc"}]}]}],"timestamp":"00:03 AM"}
]
JSONEOF
      # Log has finish AFTER the last start — turn is done
      cat > "$chat_dir/log.jsonl" <<'JSONEOF'
{"level":"INFO","timestamp":"2026-01-01T00:01:00.000Z","msg":"[send-message] Sending message"}
{"level":"INFO","timestamp":"2026-01-01T00:02:00.000Z","msg":"Start agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:05.000Z","msg":"End agent test-agent step 1 (run1)"}
{"level":"INFO","timestamp":"2026-01-01T00:02:10.000Z","msg":"Main prompt finished"}
JSONEOF
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":3,"firstPrompt":"hello","messagesSize":300,"messagesMtimeMs":3000}
JSONEOF
      ;;
    idle)
      # No messages yet (just-launched)
      cat > "$chat_dir/chat-messages.json" <<'JSONEOF'
[{"id":"divider-1","variant":"divider","content":"","blocks":[],"timestamp":"00:00 AM"}]
JSONEOF
      echo > "$chat_dir/log.jsonl"
      cat > "$chat_dir/chat-meta.json" <<'JSONEOF'
{"messageCount":0,"firstPrompt":"","messagesSize":0,"messagesMtimeMs":0}
JSONEOF
      ;;
  esac
}

cleanup() {
  if [ -n "$FAKEHOME" ] && [ -d "$FAKEHOME" ]; then
    rm -rf "$FAKEHOME"
  fi
}
