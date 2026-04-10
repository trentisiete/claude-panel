# claude-panel

Terminal dashboard for AI coding projects. See your git branches, Claude agents, token usage, and work in one screen.

Built with Zellij.

```
┌────────────┬──────────┬────────────┐
│ Branches   │ Agents   │            │
│ (auto)     │ (auto)   │  Terminal  │
├────────────┼──────────┤            │
│ git shell  │ Usage    │            │
│            │ (auto)   │            │
├────────────┴──────────┴────────────┤
│ shortcuts & paths                  │
└────────────────────────────────────┘
```

## What you see

- **Branches** — all local branches, commits ahead/behind main, last 3 commits per branch, working tree status
- **Agents** — worktrees with session counts, active Claude agents with model, branch, PID, uptime, memory, context size, current task
- **Usage** — token consumption (1h / today / week / all-time), hours remaining, output rate, model breakdown, daily bar chart
- **git shell** — interactive terminal in your project dir, run git commands
- **Terminal** — general purpose shell
- **Hints bar** — keyboard shortcuts + Claude project/memory paths

## Install

You need:

- [Zellij](https://zellij.dev) (`brew install zellij`)
- git
- bash
- python3
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (optional, for agent tracking)

```bash
git clone https://github.com/trentisiete/claude-panel.git
cd claude-panel
chmod +x claude-panel scripts/*.sh
ln -sf "$(pwd)/claude-panel" ~/.local/bin/claude-panel
```

Make sure `~/.local/bin` is in your PATH.

## Use

```bash
cd your-project
claude-panel
```

That's it. One command. It detects the git project and launches.

## Exit

- `Ctrl+Q` — quit, kills the session
- `Ctrl+O, d` — detach, session stays alive in background

## Re-enter

```bash
claude-panel
```

If the old session is alive, it reconnects. If it died, it cleans up and starts fresh.

## Kill

```bash
claude-panel --kill       # kill this project's panel
claude-panel --kill-all   # kill all panels
claude-panel --list       # see active panels
```

## Inside the panel

| Keys | What |
|------|------|
| `Ctrl+Q` | Quit |
| `Ctrl+O, d` | Detach |
| `Alt+←/→` | Switch pane |
| `Ctrl+O, n` | New pane |
| `Ctrl+O, w` | Session manager |
| `Ctrl+O, e` | Scroll mode |

## How it works

`claude-panel` generates a Zellij layout on the fly, exports your project path as env vars, and launches a named Zellij session. The monitoring panes use the alternate screen buffer so they don't flood your scrollback.

Agent tracking reads from `~/.claude/sessions/` and `~/.claude/projects/` — no API calls, no external services. Token usage is parsed from JSONL conversation logs.

## License

MIT
