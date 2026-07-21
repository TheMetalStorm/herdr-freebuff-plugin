# freebuff → herdr: stays `blocked` after popup dismissed (answer chosen OR Esc) — debug investigation

**Status:** ✅ implemented and verified (all tests pass)

Related: `DEBUG_blocked-detection.md` (the prior round, where we added screen
scraping to detect the popup in the first place). This file covers the
**inverse problem**: getting OUT of `blocked` after the popup is gone.

## Symptom

User observes, after the ask_user multiple-choice popup has been dismissed:

| User action | What happens in freebuff TUI | What herdr shows | What herdr SHOULD show |
|---|---|---|---|
| Choose answer + Submit | `Your answer: <answer>` appears (boxed), AI starts processing | stays `blocked` | `working` |
| Press Esc (no answer) | `[response interrupted]` appears, prompt returns | stays `blocked` | `idle` |

In *both* scenarios the state was correctly `blocked` while the popup was
visible (working as of `DEBUG_blocked-detection.md`), but never transitions
*out* of `blocked` after dismissal.

## Investigation log

1. Read current `classify()` in `scripts/watcher-lib.sh:172`:

   ```sh
   classify() {
     chat_dir="$1"
     pane_id="${2:-}"
     state=$(_classify_files "$chat_dir")
     if [ "$state" = "working" ] && [ -n "$pane_id" ]; then
       screen=$(detect_blocked_screen "$pane_id")
       [ "$screen" = "blocked" ] && state=blocked
     fi
     printf '%s' "$state"
   }
   ```

   → Screen check only fires when `_classify_files` returned `working`. When
   it returns `blocked` (or `idle`), the screen is never consulted again.

2. Confirmed in `DEBUG_blocked-detection.md:10-22`: freebuff only flushes the
   chat files at `Main prompt finished`. After the user answers an ask_user
   popup, freebuff enters a new turn to process the answer; chat files remain
   showing the OLD turn (with the unresolved `ask_user` block on the last AI
   message) until the new turn finishes. Same for Esc-then-next-prompt.

3. Therefore: after the popup is dismissed, `_classify_files` keeps returning
   `blocked` for the entire duration of the next turn (or until the user
   types a new message). The screen check, gated on
   `state == "working"`, never runs. Result: stuck on `blocked`.

4. User-supplied markers, captured in real freebuff output:

   - **Esc abort**: `[response interrupted]` is printed in the chat before
     returning to the prompt (see `tests/fixtures/pane-ask-user.txt:4` —
     there is a `[response interrupted]` line already in that capture).
   - **Answer chosen**: `Your answer: <text>` printed, with the chosen
     answer echoed in a bordered box, then the AI starts working.

## Root cause (CONFIRMED)

The screen-check override in `classify()` (`watcher-lib.sh:172-186`) only
handles the `working → blocked` direction. It cannot handle the inverse
`blocked → working|idle` direction because:

- `_classify_files` returns `blocked` from stale chat files for the entire
  post-dismissal processing window.
- The screen check is gated on `state == "working"`, so when
  `_classify_files` says `blocked`, the screen is never re-examined.
- Without re-examining the screen, the watcher has no way to know the popup
  is gone or to choose between `working` (answered) and `idle` (Esc).

## Proposed fix

### 1. Generalize screen detection — `detect_screen_state(pane_id)`

Replace `detect_blocked_screen` (single-state matcher) with a function that
returns one of four signals by scanning visible pane content:

| Return value | Pattern (matched in order shown) |
|---|---|
| `blocked`    | `Enter select` or `↑↓ navigate` (popup is live — UNCHANGED from existing logic) |
| `interrupted` | `\[response interrupted\]`           |
| `answered`   | `Your answer:` immediately followed within ≤2 lines by a border char (`│` / `╭` / `└` etc.) — the boxed-answer echo |
| `""`         | none of the above (no signal) |

Pattern precedence matters: check `blocked` first because the popup's
"Submit" / "Enter select" hint is on screen at the same time aswiększenie any
prior "Your answer:" — but the popup only appears after the LAST turn's
output is scrolled away, so in practice `interrupted` and `Your answer:`
mark the post-dismissal state while `Enter select` marks the live state.
Testing them in order `blocked → interrupted → answered` gives the right
precedence.

### 2. `classify()` uses screen signals even when file says `blocked`

New logic (pseudo-code):

```sh
classify() {
  chat_dir="$1"
  pane_id="${2:-}"
  state=$(_classify_files "$chat_dir")

  if [ -n "$pane_id" ]; then
    sig=$(detect_screen_state "$pane_id")   # blocked | interrupted | answered | ""

    # Live popup overrides ANY file state (working→blocked in stale-mid-turn case,
    # and prevents a brief end-of-turn "idle" file classification from clearing
    # a popup that just appeared). UNCHANGED in intent from current logic.
    if [ "$sig" = "blocked" ]; then
      state=blocked
    fi

    # Resolve the file-based "blocked" indeterminate — chat files lag behind
    # the truthful signal on screen.
    if [ "$state" = "blocked" ]; then
      case "$sig" in
        interrupted) state=idle ;;      # Esc → idle
        answered)    state=working ;;   # chose answer → AI processing
        "")          ;;                  # no signal: keep file-based blocked
      esac
    fi
  fi

  printf '%s' "$state"
}
```

Key design points:

- **`sig=blocked` (popup visible)** always wins, regardless of file state.
  Here the `working → blocked` override still happens, exactly as today.
  New case: if files transiently classify to `idle` right at end-of-turn
  while the popup is appearing, popup wins — no flicker.

- **`sig=interrupted`** only overrides when files said `blocked`. It never
  overrides a file-based `working` or `idle` (e.g., if `[response interrupted]`
  is genuine scrollback from an earlier Esc, but we're now mid-turn working,
  keep `working`). **Conservative direction**: only used to escape a stale
  blocked-file state. Same applies to `answered`.

- **`sig=""`** falls back to file state. Acceptable because once the next
  turn ends, files flush and `_classify_files` correctly returns `idle` or
  `working` based on log timestamps — no further screen signal needed. The
  risky window is "answer chosen, AI processing, `Your answer:` already
  scrolled off, files still stale" — see Risks.

### 3. Keep the `pane_id`-optional contract

Without `pane_id`, screen signal is `""` and `classify()` behaves exactly
like today's `_classify_files`. All existing single-arg tests stay green.

## Tests

### New `tests/fixtures/pane-{answer-chosen,response-interrupted}.txt`

- `pane-answer-chosen.txt`: real freebuff TUI content showing `Your answer: …`
  with the answer echoed in a box (e.g. `╭ … ╮ / │ … │ / ╰ … ╯` lines) — but
  WITHOUT the live popup (`Enter select`/`↑↓ navigate` must be absent).
- `pane-response-interrupted.txt`: output containing `[response interrupted]`
  at the prompt, no live popup.

### New cases in `tests/watcher.test.sh`

- `detect_screen_state: returns blocked for live popup` (existing fixture)
- `detect_screen_state: returns interrupted for [response interrupted] fixture`
- `detect_screen_state: returns answered for "Your answer:" + box fixture`
- `detect_screen_state: returns empty for plain working output`
- `classify: file=blocked + pane=interrupted → idle`
- `classify: file=blocked + pane=answered → working`
- `classify: file=blocked + pane=blocked → blocked` (regression guard: live popup still wins)
- `classify: file=blocked + pane="" → blocked` (no signal ⇒ fall back to files)
- `classify: file=working + pane=interrupted → working` (interrupted pattern does NOT clear a true working state — guard against scrollback false-match)
- `classify: file=idle + pane=interrupted → idle` (no override outside the file==blocked case)
- `classify: file=working + pane=blocked → blocked` (existing assertion kept)

### Update `tests/fixtures/herdr-stub.sh`

Existing `pane read` plumbing is fine. New env vars:
`HERDR_STUB_PANE_CONTENT_<ID>` already points at a fixture file or inline
string. We just point different tests at different fixtures by overriding
the env var per test (the existing pattern).

## Risks / regressions

1. **Transient window risk — `Your answer:` scrolled off before next poll
   (700ms) while files still say `blocked`.** Mitigations:
   - Increase `--lines` from 80 to 200 in the `herdr pane read` call so we
     scan more scrollback and the marker survives longer.
   - The poll cycle is 700ms (per `status-watcher.sh:62`); the
     `Your answer:` box typically persists for several seconds (the AI's
     next message has to scroll it off), so catch rate should be high.
   - Worst case: if we miss `Your answer:`, files stay `blocked` until the
     AI's new turn ends (at which point `Main prompt finished` flushes
     them and we self-correct to `idle`). Acceptable: bounded by next
     `Main prompt finished` log line.

2. **`Your answer:` text could appear outside the popup-dismissal flow**,
   e.g., as part of an AI message quoting the user. Mitigation: require the
   answer-echo to come WITHIN ≤2 lines of `Your answer:` AND include a box
   drawing char (`│`/`╭`/`╰`). Single-line `Your answer:` without the box
   does not match.

3. **`[response interrupted]` appears for non-Esc reasons** (user Ctrl-C, AI
   hitting its own stop). Mapping any such interruption to `idle` is the
   desired behavior — Esc and Ctrl-C both return freebuff to the prompt.
   Not a regression.

4. **`detect_blocked_screen` rename to `detect_screen_state`.** Existing
   tests currently call the old name. Update references (or keep an alias
   for one release). Prefer rename + test update to keep names honest.

5. **Backward compat without `pane_id`.** Unchanged — all single-arg
   `classify` calls keep prior behavior. No new screen check fires.

6. **Extra `herdr pane read` cost per poll while files say `blocked`.**
   Previously the screen check only ran during `working`. Now it runs
   whenever pane_id is set AND (file=working OR file=blocked). Cost ≈ 50ms
   per call at 700ms cadence → ~7% CPU on the watcher process during popup.
   Acceptable.

## Verification

- `sh tests/run.sh` — must include the new cases above. Expected count
  grows from 46 → 57.
- Live:
  1. In freebuff: "ask me a multiple choice question" → herdr shows `blocked`
     while popup is visible.
  2. Select an option + Enter → herdr shows `working` while AI processes.
  3. After AI finishes turn → herdr shows `idle` (green check).
  4. Repeat 1, then Esc → herdr shows `idle` (NOT `blocked`).
  5. Repeat 4 two more times back-to-back — verify no flicker, no stuck
     state across multiple consecutive Esc sequences.

## Doubts (open questions for the user)

- The exact visual form of the post-answer "Your answer:" box. I have not
  personally captured this — user describes it as "Your answer: and the
  answer we chose in a box". The matcher should be tolerant: match
  `Your answer:` within ≤2 lines of any of `╭`, `│`, `╰`, `└`, `┌`. If the
  real rendering differs (e.g., uses ASCII `-` / `|` only), the fixture
  and matcher both need adjusting — pin this before we implement.
  ANSWER: to be safe check for all the symbols
- Whether `[response interrupted]` is also printed when the AI hits its
  own end-of-output stop (not just on user Esc). If so, mapping to `idle`
  is still correct.
  ANSWER: no it doesnt

