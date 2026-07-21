# Test Notes / Known Deviations

## State semantics
Herdr's state vocabulary (confirmed via schema):
  - `blocked` = agent needs input/approval/decision
  - `working` = actively running
  - `done`    = finished, unseen by user
  - `idle`    = finished/waiting, seen
  - `unknown` = cannot classify

The plugin never reports `done` via `pane.report-agent` (that RPC only accepts
`idle|working|blocked|unknown`). Instead, it reports `idle` when a turn finishes,
and herdr internally renders the `done` state (green checkmark) during the
`working -> idle` transition. This matches the opencode and commandcode reference
integrations.

## How Herdr renders the 5 states (observed via schema + opencode plugin)
- `working`  -> orange/yellow filled dot
- `done`     -> green unfilled dot  
- `blocked`  -> filled dot glyph
- `idle`     -> minimal/empty
- `unknown`  -> red marker

The `label()` call (`report-metadata --display-agent freebuff`) must run once at
watcher startup, or the space/tab surface shows red `unknown` dot.

## File-polling approach (not hooks)
Freebuff has no hook system. This plugin polls files at
`~/.config/manicode/projects/<slug>/chats/<timestamp>/`. The polling interval is
0.7s, which means state changes are reported within ~1s of happening.

## Fake freebuff binary
The test fixture `tests/fixtures/bin/freebuff` is a simple `sleep` loop. It does
not write real chat files. Tests create fixture state files manually via
`make_fake_chat`.

## Process tracking
The watcher checks `kill -0 "$LAUNCHER_PID"` to detect when freebuff exits.
On SIGKILL, the PID disappears immediately so the watcher exits on the next
poll cycle (~0.7s delay). This is not tested in CI because it requires killing
processes, which is fragile in test environments.

## `done` test limitation
When the watcher reports `idle` after a completed turn, herdr should render this
as `done`. This cannot be tested with the herdr-stub alone (the stub is
text-based and doesn't simulate herdr's UI state machine). Manual verification
with a real herdr instance is required.
