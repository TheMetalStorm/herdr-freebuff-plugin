# Plan: freebuff → herdr integration

## Decision A (locked in)
The plugin **never sends `done`** through `pane.report-agent`. After a finished turn it sends `idle`; herdr's built-in `working → idle` transition renders the green-checkmark `done` state for the user, then flips to `idle` once the tab is viewed. This matches the opencode and commandcode reference integrations exactly.

## Goal
A herdr plugin that launches `freebuff` and reports **working / blocked / idle** (rendered as `done` by herdr on turn completion) by **polling freebuff's per-chat files on disk**. No PTY scraping, no child-process tree walking, no internal hooks (freebuff has none).

## Architecture

### Two entrypoints, same code path
1. **Plugin pane** → `launch.sh` → resolves `freebuff` (prefers `~/.local/bin/freebuff` wrapper) → `exec`
2. **Manual terminal** → user types `freebuff` → finds wrapper on PATH → wrapper runs

In both cases, the **wrapper** (`~/.local/bin/freebuff`, installed by `setup.sh`) is what actually runs. It:
1. Scans PATH to find the real freebuff binary, skipping its own location.
2. If `HERDR_ENV=1 && HERDR_PANE_ID` is set, spawns `status-watcher.sh` in background (passing `$$` as the launcher PID).
3. `exec`s the real freebuff binary with all original argv.

The watcher survives the exec because it was forked before exec. After exec the original PID becomes freebuff itself, so the watcher's `kill -0 $LAUNCHER_PID` loop tracks freebuff's lifetime.

### classify() precedence (bugfix applied)
1. **Timeline first**: compute `last_start` (newer of `Start agent` / `[send-message]`) and `last_finish` (`Main prompt finished`).
2. **If `last_finish >= last_start`** → turn is done → skip blocked check, fall through to idle/done logic.
3. **Otherwise (turn is live)**: check for unresolved `ask-user` block → `blocked`.
4. **Then**: working (start > finish) or idle (finish >= start).

This fixes the stale-blocked bug: an `ask-user` block on the last AI message no longer causes perpetual `blocked` after the turn has finished (`Main prompt finished` emitted).

## Files

### Core scripts
| File | Role |
|---|---|
| `herdr-plugin.toml` | Manifest: 3 panes + 2 actions |
| `scripts/launch.sh` | Pane entrypoint; resolves freebuff (prefers wrapper); execs with args |
| `scripts/freebuff-wrapper.sh` | PATH wrapper template; spawns watcher; execs real freebuff |
| `scripts/status-watcher.sh` | Lifecycle poller; reports to herdr via `pane.report-agent` |
| `scripts/watcher-lib.sh` | Shared: `classify`, `detect_blocked`, `last_matching_ts`, `find_newest_chat` |
| `scripts/common.sh` | `ensure_agent_detection`, `in_herdr` |
| `scripts/setup.sh` | Seeds agent-detection + installs wrapper (supports `--uninstall`) |
| `scripts/notify.sh` | Sends herdr notification |
| `config/agent-detection/freebuff.toml` | Cmdline detection override |

### Tests (39 test cases, all passing)
| File | Tests |
|---|---|
| `tests/common.test.sh` | 4 (in_herdr, ensure_agent_detection) |
| `tests/launch.test.sh` | 6 (modes, wrapper preference, error cases) |
| `tests/watcher.test.sh` | 13 (classify variants, detect_blocked, last_matching_ts, find_newest_chat) |
| `tests/wrapper.test.sh` | 5 (exec, graceful fail, watcher spawn only in herdr) |
| `tests/setup.test.sh` | 8 (install, uninstall, no-op uninstall) |
| `tests/e2e.test.sh` | 5 (full watcher lifecycle with fake freebuff) |
| `tests/notify.test.sh` | 2 (sends notification, fails outside herdr) |

## Key commands
- **Setup**: `herdr plugin action invoke freebuff.integration.setup` or `sh scripts/setup.sh`
- **Uninstall**: `sh scripts/setup.sh --uninstall` (removes wrapper; agent-detection config left in place)
- **Test**: `sh tests/run.sh`
- **Re-link**: `herdr plugin unlink freebuff.integration && herdr plugin link /home/simon/Dev/freebuff-herdr-integration`

## Architecture diagram
```
User types "freebuff" or opens plugin pane
         │
         ▼
  ~/.local/bin/freebuff ──── (wrapper, installed by setup.sh)
         │
         ├── spawns status-watcher.sh ──── polls chat files → reports to herdr
         │
         └── execs real freebuff (npm wrapper → ELF)
                      │
                      ▼
              freebuff TUI (interactive)
```
