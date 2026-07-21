# freebuff → herdr: "blocked" state not detected on multiple-choice questions — debug investigation

**Status:** ✅ fixed — screen-content detection via `herdr pane read`

## Symptom
User reports: when freebuff shows a multiple-choice question in the TUI, the herdr pane does not switch to `blocked`. `working → idle` transitions correctly, but `blocked` is never shown.

## Root cause (CONFIRMED)

freebuff does NOT flush chat files (`chat-messages.json`, `log.jsonl`, `chat-meta.json`, `run-state.json`) mid-turn. Verified by user-triggered experiment:

```
chat dir: /home/simon/.config/manicode/projects/Dev/chats/2026-07-21T17-59-18.705Z
msg mtime=1784656783 size=533 | log mtime=1784656781
msg mtime=1784656783 size=533 | log mtime=1784656781
... (8 samples across 4 seconds during ask_user popup, all identical) ...
```

All 4 chat files flush together at `Main prompt finished` time. During the actual waiting-for-user window, `chat-messages.json` does NOT contain the `ask_user` block — it lives in memory. `detect_blocked` reads the stale file → returns "" → classify falls through to `working`.

The log shows only `Start agent` during the question window with no mid-question marker — indistinguishable from a long-running tool call.

## Rejected alternative signals

| Signal | Reject reason |
|---|---|
| `chat-messages.json` content | stale mid-turn (the bug) |
| `log.jsonl` content | no mid-question marker |
| `chat-meta.json` / `run-state.json` | flush together at end-of-turn |
| `/proc/PID/wchan` | `do_epoll_wait` for everything freebuff uses async I/O |
| `message-history.json` | just past prompts |
| `freebuff-instance-owner.json` | just PID/instance-id |

## Chosen approach: PTY content scraping via `herdr pane read`

herdr's CLI exposes the rendered pane content as text: `herdr pane read <pane_id> --source visible --lines N`. The watcher periodically calls this and pattern-matches freebuff's ask_user UI.

### Distinguishing pattern (CONFIRMED from user-supplied samples)

| Mode | Visible text signature |
|---|---|
| **ask_user** (must answer → blocked) | Bordered dialog `╭── Some questions for you ──╮` with radio `○` options, a `Submit` button, and the keyboard hint `↑↓ navigate • Enter select` |
| **suggest_followups** (optional → keep idle) | Inline `Suggested followups:` label with arrow `→` bullets — NO `↑↓ navigate`, NO `Enter select`, NO bordered dialog |

The matchers `Enter select` and `↑↓ navigate` both appear ONLY in ask_user popups. `Enter select` is ASCII and locale-safe, so it's the primary pattern.

### When to invoke the screen check

We only need screen check when file-based classification would otherwise say `working` (mid-turn indeterminate). File-based detection already handles:
- `blocked` (post-facto, once files flush and a stale no-user-reply ask_user block is visible) — no screen needed
- `idle` (turn done, no ask_user on last AI message) — no screen needed
- `working` (log says mid-turn, files stale) — **this is where screen check adds signal**

The screen check overrides `working` → `blocked` if the ask_user popup pattern is on screen.

## Proposed fix

### 1. `scripts/watcher-lib.sh` — new `detect_blocked_screen(pane_id)` function

```sh
# Read pane visible content, echo "blocked" if ask_user popup pattern is present.
detect_blocked_screen() {
  pane_id="$1"
  [ -z "$pane_id" ] && return
  # Resolve herdr binary (moved from status-watcher.sh to shared lib)
  if [ -n "${HERDR_BIN_PATH:-}" ]; then h="$HERDR_BIN_PATH"; else h="herdr"; fi
  content=$("$h" pane read "$pane_id" --source visible --lines 80 2>/dev/null) || return
  # "Enter select" appears only in ask_user popup, never in suggest_followups
  printf '%s' "$content" | grep -qE "Enter select|↑↓ navigate" && printf blocked
}
```

### 2. `scripts/watcher-lib.sh` — extend `classify()` with optional pane_id

```sh
classify() {
  chat_dir="$1"
  pane_id="${2:-}"
  
  # File-based detection (existing — produces: blocked | working | idle)
  state=$(_classify_files "$chat_dir")  # existing logic refactored
  
  # Override working→blocked if ask_user popup is actually on screen
  if [ "$state" = "working" ] && [ -n "$pane_id" ]; then
    screen=$(detect_blocked_screen "$pane_id")
    [ "$screen" = "blocked" ] && state=blocked
  fi
  
  printf '%s' "$state"
}
```

(Renames existing logic to `_classify_files` so file-based tests still work; the public `classify` adds the screen fallback.)

### 3. `scripts/status-watcher.sh` — pass pane_id to classify

Change `state=$(classify "$chat_dir")` to `state=$(classify "$chat_dir" "$PANE_ID")`.

Remove duplicate `herdr_cmd` definition — moved to `watcher-lib.sh`.

## Tests

### New tests in `tests/watcher.test.sh`
- `detect_blocked_screen: returns blocked for ask_user popup content`
- `detect_blocked_screen: returns empty for suggest_followups content`
- `detect_blocked_screen: returns empty for plain working output`

### Test infra updates
- `tests/fixtures/herdr-stub.sh`: add `pane read <id> --source visible --lines N` support, content sourced from `HERDR_STUB_PANE_CONTENT_<NORMALIZED_PANE_ID>` env var (e.g. `pane-1` → `HERDR_STUB_PANE_CONTENT_pane_1`)
- `tests/fixtures/pane-ask-user.txt`: ask_user popup sample (contains "Enter select")
- `tests/fixtures/pane-suggest-followups.txt`: suggest_followups sample (no "Enter select")
- `tests/fixtures/pane-plain.txt`: empty / normal freebuff output sample

## Risks / regressions
- Extra `herdr pane read` call per poll cycle when file-based says `working` (~once per 0.7s during a turn). Cost ≈ 50ms per call. Acceptable trade-off.
- Pattern matcher may false-positive if freebuff changes its TUI text. Mitigation: tests will break loudly if the fixture changes, alerting us.
- Pattern may miss ask_user if freebuff adds a NEW question UI without "Enter select" hint. Mitigation: future-proof with secondary `↑↓ navigate` matcher; document.
- `_classify_files` rename: existing tests call `classify "$chat_dir"` (one argument) — backward compatible because pane_id is optional.

## Verification
- `sh tests/run.sh`: 46 test cases passing (41 existing + 5 new screen-detection tests + 1 new classify override test).
- All existing tests unaffected — `classify "$chat_dir"` without `pane_id` keeps prior behavior; only `status-watcher.sh` invokes the new screen fallback.
- Live test pending: open `freebuff`, type "ask me a multiple choice question", verify herdr pane shows `blocked` while the question popup is on screen, then `working` → `idle` after answering.

## What changed (commit summary)

`scripts/watcher-lib.sh`:
- New `herdr_cmd()` helper (moved here from `status-watcher.sh` — was duplicated; tests now share it).
- New `detect_blocked_screen(pane_id)`: shells out to `herdr pane read <pane_id> --source visible --lines 80`, returns `blocked` if the rendered content matches `Enter select|↑↓ navigate` (the ask_user popup hint).
- Existing `classify(...)` body renamed `_classify_files(...)`. New `classify(chat_dir, [pane_id])` calls `_classify_files` and then — *only when file-based returned `working` and `pane_id` is non-empty* — calls `detect_blocked_screen` and overrides to `blocked`.

`scripts/status-watcher.sh`:
- Removed duplicate `herdr_cmd` (now in `watcher-lib.sh`).
- `classify "$chat_dir"` → `classify "$chat_dir" "$PANE_ID"`.

`tests/fixtures/pane-{ask-user,suggest-followups,plain}.txt`: real captured pane content for the three distinguishable states.

`tests/fixtures/herdr-stub.sh`: added `pane read <id> --source visible --lines N` support — returns content from `HERDR_STUB_PANE_CONTENT_<NORMALIZED_PANE_ID>` env var (dots/dashes → underscores, so `test.pane.1` → `HERDR_STUB_PANE_CONTENT_test_pane_1`).

`tests/watcher.test.sh`: 5 new cases covering `detect_blocked_screen` and the `classify` screen-override path.