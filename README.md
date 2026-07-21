# herdr-freebuff-plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Makes [Freebuff](https://freebuff.com) a first-class agent inside [Herdr](https://herdr.dev), the terminal multiplexer for coding agents.

**Lifecycle state** (`idle` / `working` / `blocked`) is reported to the herdr pane socket automatically — no manual status commands. The plugin works via disk-file polling supplemented by PTY content scraping for state transitions that freebuff does not flush to disk promptly.

## Features

- **Lifecycle reporting** — freebuff pane shows `idle` → `working` → `blocked` → `idle` (green checkmark `done`). Detects:
  - Normal processing turns (`working` / `idle` via `log.jsonl` timestamps)
  - `ask_user` multiple-choice popups (`blocked` via PTY content scraping)
  - Answer chosen (`working` via screen-detected answer echo)
  - Esc abort (`idle` via `[response interrupted]` marker)
- **Session restore** — reports the freebuff session ID so herdr can resume after a server restart.
- **Sidebar detection** — seeds an agent-detection override so herdr recognises the `freebuff` process.
- **Launch panes** — new task, resume last session, or resume a named session.
- **Notifications** — a `notify` action sends a herdr toast.

## Requirements

- Herdr >= 0.7.0
- `freebuff` on your `PATH` (`npm i -g freebuff`)

## Install

```bash
herdr plugin link /path/to/herdr-freebuff-plugin
herdr plugin action invoke freebuff.integration.setup
```

Or from GitHub (requires repo access):

```bash
herdr plugin install TheMetalStorm/herdr-freebuff-plugin
herdr plugin action invoke freebuff.integration.setup
```

The `setup` action seeds the agent-detection override for the `freebuff` binary.

## Use

Open a freebuff pane via the plugin entrypoints:

```bash
herdr plugin pane open --plugin freebuff.integration --entrypoint task
herdr plugin pane open --plugin freebuff.integration --entrypoint resume-last
herdr plugin pane open --plugin freebuff.integration --entrypoint resume-named
```

Or just type `freebuff` in any pane — a PATH wrapper (`~/.local/bin/freebuff`) spawns the lifecycle watcher automatically:

```bash
freebuff                        # new session
freebuff --continue             # resume last session
freebuff --session <id>         # resume named session
```

Send a notification:

```bash
herdr plugin action invoke freebuff.integration.notify "Build done" "api workspace"
```

Keybinding:

```toml
[[keys.command]]
key = "prefix+f"
type = "plugin_pane"
command = "freebuff.integration.task"
description = "Freebuff: new task"
```

### Notifications (blocked → toast + sound)

By default herdr suppresses toasts for the active tab and has notifications off.
Enable in `~/.config/herdr/config.toml`:

```toml
[ui.toast]
delivery = "herdr"
delay_seconds = 1

[ui.toast.herdr]
position = "bottom-right"

[ui.sound]
enabled = true
```

## How status reporting works

This plugin mirrors herdr's OpenCode integration but with a key difference:
freebuff has **no internal hook system**. Instead, the plugin spawns a detached
watcher process that polls freebuff's per-chat state files on disk, supplemented
by PTY screen scraping for mid-turn state.

### State detection matrix

| State | Primary signal | Fallback / supplement | When |
|---|---|---|---|
| `idle` | No chat dir or `Main prompt finished` newer than last `Start agent` | — | Just launched, or turn completed |
| `working` | `[send-message]` or `Start agent step N` newer than last `Main prompt finished` | `Your answer:` + box on screen (answer chosen, AI processing) | Agent is processing or just received an answer |
| `blocked` | `ask-user` block in last AI message (no user reply after it) in `chat-messages.json` | `Enter select` / `↑↓ navigate` on screen (live popup, not yet flushed to disk) | Freebuff presents up/down-arrow choices |
| `idle` (Esc) | — | `[response interrupted]` on screen (Esc abort, popup gone but files still stale) | User pressed Esc to cancel a question |

### Why screen scraping?

Freebuff flushes chat files (`chat-messages.json`, `log.jsonl`) only at
end-of-turn. During the mid-turn "live ask_user popup" window, the question
block is not yet on disk — file-polling alone cannot detect it. Similarly,
after the user answers or Esc's, the files stay stale (still showing the old
unresolved `ask_user` block) until the next `Main prompt finished`.

The watcher uses `herdr pane read` to inspect visible pane content and detects
these transient UI states by their unique on-screen markers.

### Polling

State is checked every ~700ms from:

```
~/.config/manicode/projects/<project-slug>/chats/<timestamp>/
    chat-messages.json
    log.jsonl
    chat-meta.json
```

## Files

| File | Role |
|---|---|
| `herdr-plugin.toml` | Manifest: panes, setup action, notify action |
| `scripts/launch.sh` | Pane entrypoint; execs `freebuff` |
| `scripts/status-watcher.sh` | Detached lifecycle watcher polling to herdr socket |
| `scripts/watcher-lib.sh` | Shared classify/detect helpers (file-based + screen) |
| `scripts/common.sh` | Shared helpers (agent-detection seeding) |
| `scripts/setup.sh` | Seeds agent-detection override; installs PATH wrapper |
| `scripts/notify.sh` | Sends a herdr notification |
| `scripts/freebuff-wrapper.sh` | Template for `~/.local/bin/freebuff` (spawns watcher on every invocation) |
| `config/agent-detection/freebuff.toml` | Agent-detection override for `freebuff` |
| `tests/` | Test suite (59+ assertions across 7 suites) |

## Notes

- Launching uses plugin **panes** (real PTYs); actions run detached without a TTY and `freebuff` requires one.
- Windows is supported via Git Bash (scripts are POSIX `sh`).
- Verify agent-detection schema with `herdr api schema --json`; adjust `config/agent-detection/freebuff.toml` if field names differ on your version.

## License

MIT — see [LICENSE](LICENSE).
