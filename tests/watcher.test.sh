# Tests for scripts/watcher-lib.sh (classify function)
. "$(dirname "$0")/lib.sh"

# Source watcher-lib to get classify, detect_blocked, last_matching_ts, json_get
. "$(dirname "$0")/../scripts/watcher-lib.sh"

t_title "classify: idle when no chat dir"
result=$(classify "/nonexistent/dir")
t_is "idle" "$result" "no chat dir -> idle"

t_title "classify: blocked with unresolved ask-user (old format)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
result=$(classify "$chat_dir")
t_is "blocked" "$result" "ask-user block with no user reply -> blocked"
rm -rf "$chat_dir"

t_title "classify: blocked with tool/ask_user (new format)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked-new"
result=$(classify "$chat_dir")
t_is "blocked" "$result" "tool/ask_user block with no user reply -> blocked"
rm -rf "$chat_dir"

t_title "classify: working from in-progress agent step"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
result=$(classify "$chat_dir")
t_is "working" "$result" "Start agent after last finish -> working"
rm -rf "$chat_dir"

t_title "classify: idle (done) after Main prompt finished"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "done"
result=$(classify "$chat_dir")
t_is "idle" "$result" "Main prompt finished after start -> idle (done)"
rm -rf "$chat_dir"

t_title "classify: blocked when ask-user on finished turn (freebuff model)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "stale-blocked"
result=$(classify "$chat_dir")
t_is "blocked" "$result" "ask-user with Main prompt finished -> blocked (freebuff finishes turn before showing question)"
rm -rf "$chat_dir"

t_title "classify: idle when no messages"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "idle"
result=$(classify "$chat_dir")
t_is "idle" "$result" "no conversation -> idle"
rm -rf "$chat_dir"

t_title "detect_blocked: detects ask-user (old format)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
result=$(detect_blocked < "$chat_dir/chat-messages.json" 2>/dev/null)
t_is "blocked" "$result" "detect_blocked returns blocked for ask-user block"
rm -rf "$chat_dir"

t_title "detect_blocked: detects ask-user (new tool format)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked-new"
result=$(detect_blocked < "$chat_dir/chat-messages.json" 2>/dev/null)
t_is "blocked" "$result" "detect_blocked returns blocked for tool/ask_user block"
rm -rf "$chat_dir"

t_title "detect_blocked: no ask-user on working"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
result=$(detect_blocked < "$chat_dir/chat-messages.json" 2>/dev/null)
t_is "" "$result" "detect_blocked returns empty for working"
rm -rf "$chat_dir"

t_title "last_matching_ts: finds Start agent"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
result=$(last_matching_ts "Start agent" < "$chat_dir/log.jsonl")
t_is "2026-01-01T00:02:10.000Z" "$result" "finds last start agent timestamp"
rm -rf "$chat_dir"

t_title "last_matching_ts: finds Main prompt finished"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "done"
result=$(last_matching_ts "Main prompt finished" < "$chat_dir/log.jsonl")
t_is "2026-01-01T00:02:10.000Z" "$result" "finds main prompt finished timestamp"
rm -rf "$chat_dir"

t_title "find_newest_chat: finds chat across projects"
_old_home="$HOME"
export HOME=$(mktemp -d)
mkdir -p "$HOME/.config/manicode/projects/testproj/chats/2026-01-01T00-00-00.000Z"
result=$(find_newest_chat)
t_is "$HOME/.config/manicode/projects/testproj/chats/2026-01-01T00-00-00.000Z" "$result" "finds chat dir"
rm -rf "$HOME"
export HOME="$_old_home"
unset _old_home

t_title "find_newest_chat: empty when no projects"
_old_home="$HOME"
export HOME=$(mktemp -d)
result=$(find_newest_chat)
t_is "" "$result" "empty when no projects"
rm -rf "$HOME"
export HOME="$_old_home"
unset _old_home

t_title "last_matching_ts: no match returns empty"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "idle"
result=$(last_matching_ts "Start agent" < "$chat_dir/log.jsonl")
t_is "" "$result" "no match -> empty string"
rm -rf "$chat_dir"

# --- detect_screen_state tests ---
# These need to stub `herdr pane read` via the fake herdr binary.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HERDR_BIN_PATH="$PROJECT_ROOT/tests/fixtures/herdr-stub.sh"

t_title "detect_screen_state: returns blocked for ask_user popup"
HERDR_STUB_PANE_CONTENT_test_pane_1="$PROJECT_ROOT/tests/fixtures/pane-ask-user.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_1
result=$(detect_screen_state "test.pane.1")
t_is "blocked" "$result" "ask_user popup detected via screen content"

t_title "detect_screen_state: returns interrupted for [response interrupted]"
HERDR_STUB_PANE_CONTENT_test_pane_4="$PROJECT_ROOT/tests/fixtures/pane-response-interrupted.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_4
result=$(detect_screen_state "test.pane.4")
t_is "interrupted" "$result" "[response interrupted] detected via screen content"

t_title "detect_screen_state: returns answered for 'Your answer:' + box"
HERDR_STUB_PANE_CONTENT_test_pane_5="$PROJECT_ROOT/tests/fixtures/pane-answer-chosen.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_5
result=$(detect_screen_state "test.pane.5")
t_is "answered" "$result" "'Your answer:' with boxed answer detected via screen content"

t_title "detect_screen_state: returns thinking for suggest_followups"
HERDR_STUB_PANE_CONTENT_test_pane_2="$PROJECT_ROOT/tests/fixtures/pane-suggest-followups.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_2
result=$(detect_screen_state "test.pane.2")
t_is "thinking" "$result" "suggest_followups has • Thinking -> thinking"

t_title "detect_screen_state: returns thinking for plain working output"
HERDR_STUB_PANE_CONTENT_test_pane_3="$PROJECT_ROOT/tests/fixtures/pane-plain.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_3
result=$(detect_screen_state "test.pane.3")
t_is "thinking" "$result" "plain thinking output has • Thinking -> thinking"

t_title "detect_screen_state: returns empty for truly idle output"
HERDR_STUB_PANE_CONTENT_test_pane_6="$PROJECT_ROOT/tests/fixtures/pane-idle.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_6
result=$(detect_screen_state "test.pane.6")
t_is "" "$result" "idle pane with no signals -> empty"

t_title "detect_screen_state: empty pane_id returns empty silently"
result=$(detect_screen_state "")
t_is "" "$result" "empty pane_id -> empty result"

t_title "classify: screen overrides working -> blocked"
# Build a working chat dir (file-based returns working), then a pane_id whose
# screen shows ask_user popup -> classify should return "blocked".
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
HERDR_STUB_PANE_CONTENT_test_pane_1="$PROJECT_ROOT/tests/fixtures/pane-ask-user.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_1
result=$(classify "$chat_dir" "test.pane.1")
t_is "blocked" "$result" "working + ask_user on screen -> blocked"
rm -rf "$chat_dir"

t_title "classify: screen with suggest_followups does not override working"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
HERDR_STUB_PANE_CONTENT_test_pane_2="$PROJECT_ROOT/tests/fixtures/pane-suggest-followups.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_2
result=$(classify "$chat_dir" "test.pane.2")
t_is "working" "$result" "working + suggest_followups -> working (not blocked)"
rm -rf "$chat_dir"

t_title "classify: file=blocked + pane=interrupted -> idle"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
HERDR_STUB_PANE_CONTENT_test_pane_4="$PROJECT_ROOT/tests/fixtures/pane-response-interrupted.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_4
result=$(classify "$chat_dir" "test.pane.4")
t_is "idle" "$result" "blocked files + [response interrupted] on screen -> idle"
rm -rf "$chat_dir"

t_title "classify: file=blocked + pane=answered -> working"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
HERDR_STUB_PANE_CONTENT_test_pane_5="$PROJECT_ROOT/tests/fixtures/pane-answer-chosen.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_5
result=$(classify "$chat_dir" "test.pane.5")
t_is "working" "$result" "blocked files + 'Your answer:' box on screen -> working"
rm -rf "$chat_dir"

t_title "classify: file=blocked + pane=blocked -> blocked"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
HERDR_STUB_PANE_CONTENT_test_pane_1="$PROJECT_ROOT/tests/fixtures/pane-ask-user.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_1
result=$(classify "$chat_dir" "test.pane.1")
t_is "blocked" "$result" "blocked files + live popup on screen -> blocked"
rm -rf "$chat_dir"

t_title "classify: file=blocked + pane='' -> blocked (no screen override)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
result=$(classify "$chat_dir")
t_is "blocked" "$result" "blocked files + no pane_id -> blocked (no screen check)"
rm -rf "$chat_dir"

t_title "classify: file=working + pane=interrupted -> working (no override)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
HERDR_STUB_PANE_CONTENT_test_pane_4="$PROJECT_ROOT/tests/fixtures/pane-response-interrupted.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_4
result=$(classify "$chat_dir" "test.pane.4")
t_is "working" "$result" "working files + [response interrupted] on screen -> working (not overridden)"
rm -rf "$chat_dir"

t_title "classify: file=idle + pane=interrupted -> idle (no override)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "idle"
HERDR_STUB_PANE_CONTENT_test_pane_4="$PROJECT_ROOT/tests/fixtures/pane-response-interrupted.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_4
result=$(classify "$chat_dir" "test.pane.4")
t_is "idle" "$result" "idle files + [response interrupted] on screen -> idle (not overridden)"
rm -rf "$chat_dir"

t_title "classify: file=blocked + pane=thinking -> working"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "blocked"
HERDR_STUB_PANE_CONTENT_test_pane_3="$PROJECT_ROOT/tests/fixtures/pane-plain.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_3
result=$(classify "$chat_dir" "test.pane.3")
t_is "working" "$result" "blocked files + • Thinking on screen -> working"
rm -rf "$chat_dir"

t_title "classify: file=working + pane=thinking -> working (no override)"
chat_dir=$(mktemp -d)
make_fake_chat "$chat_dir" "working"
HERDR_STUB_PANE_CONTENT_test_pane_3="$PROJECT_ROOT/tests/fixtures/pane-plain.txt" \
  export HERDR_STUB_PANE_CONTENT_test_pane_3
result=$(classify "$chat_dir" "test.pane.3")
t_is "working" "$result" "working files + • Thinking on screen -> working (not overridden)"
rm -rf "$chat_dir"

unset HERDR_STUB_PANE_CONTENT_test_pane_1 HERDR_STUB_PANE_CONTENT_test_pane_2 \
  HERDR_STUB_PANE_CONTENT_test_pane_3 HERDR_STUB_PANE_CONTENT_test_pane_4 \
  HERDR_STUB_PANE_CONTENT_test_pane_5 HERDR_STUB_PANE_CONTENT_test_pane_6
unset HERDR_BIN_PATH
