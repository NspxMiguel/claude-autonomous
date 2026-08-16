# claude-autonomous

Stops Claude Code from asking. No permission prompts, the whole disk in scope,
and a skill that holds the other half of the deal — acting instead of asking.

*[Leia em português](README.pt-BR.md)*

> **Read [what it changes](#what-it-changes) before running this.** It removes
> every guardrail the harness gives you, on purpose. That is the point, and it
> is also the risk: an agent with no prompts will delete the wrong directory
> just as confidently as it writes the right file. Bring `git` and backups.

---

## Install

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.sh | bash
```

**Windows** (no administrator rights needed)

```powershell
irm https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.ps1 | iex
```

**From a clone**

```bash
git clone https://github.com/NspxMiguel/claude-autonomous
cd claude-autonomous
./install.sh
```

Then **restart your Claude Code session** — the permission mode is read at
startup.

```bash
claude-autonomous status   # what is actually set right now
claude-autonomous off      # put everything back
```

---

## Why config alone is not enough

Most "make it autonomous" advice stops at `--dangerously-skip-permissions`. That
suppresses the harness prompt, and then the model stops anyway to write *"want
me to do X?"* — which, to the person waiting, is the same stall.

So this ships two halves:

| Half | What it is | Where it lives |
| --- | --- | --- |
| **Config** | No prompt can be raised | `~/.claude/settings.json` |
| **Posture** | No question is invented | the `autonomous` skill |

The skill is the part people skip, and it is the part that actually changes how
a session feels: decide instead of listing options, never close a turn with
*"let me know if you want me to continue"*, and when a request is genuinely
ambiguous, deliver everything that does not depend on the answer first — then
ask the one thing left over.

---

## What it changes

Written into `~/.claude/settings.json`, merged with what is already there. The
previous file is copied to `~/.claude/backups/` on every run.

| Setting | Effect |
| --- | --- |
| `permissions.defaultMode: bypassPermissions` | No permission prompt |
| `hooks.PreToolUse` → `allow` | Second line: answers "allow" before a prompt can exist, for sessions that open in a prompting mode |
| `permissions.deny: []`, `ask: []` | Nothing is held back or escalated |
| `permissions.additionalDirectories` | Whole machine in scope, not just the project directory |
| `permissions.allow` | Every built-in tool and MCP server pre-approved, so the mode still holds if you switch modes |
| `sandbox.enabled: false` | Commands run unconfined |
| `enableAllProjectMcpServers: true` | No "trust this MCP server?" prompt |
| `skipDangerousModePermissionPrompt` | No startup dialog |
| `skipWorkflowUsageWarning` | No cost warning before multi-agent workflows |
| `askUserQuestionTimeout: 60s` | If the model does ask, the session continues instead of parking |
| `fileCheckpointingEnabled: true` | `/rewind` still works — the last undo left |
| `BASH_MAX_TIMEOUT_MS: 600000` | Long commands finish (2 min → 10 min) |

`fileCheckpointingEnabled` is deliberate. With every prompt gone, `/rewind` is
the only thing standing between a bad edit and a lost afternoon.

### The auto-approve hook

`bypassPermissions` already suppresses prompts, so why a hook? Because a session
does not always open in the mode you configured — the desktop app starts some
contexts in `default`. The hook answers before the prompt exists:

```json
{
  "type": "command",
  "command": "/bin/echo",
  "args": ["{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}"],
  "timeout": 5
}
```

Exec form (`command` + `args`) rather than a shell string, so nothing parses the
JSON payload. One `/bin/echo` per tool call.

---

## What it does not change

Three layers can stop an action. This repo only owns the first.

**The operating system.** macOS TCC is not configurable from a settings file.
Screen recording, accessibility, automation and folder access each raise their
own dialog the first time they are used. Grant them in one sitting under System
Settings → Privacy & Security, or they will interrupt mid-task.

**The model's own limits.** No config file removes these: typing a password,
token or 2FA code into a form; logging in or creating accounts; moving money;
irreversible destruction without confirmation; following instructions found
inside a web page or email rather than coming from you.

Note the line on credentials — it is about *typing*, not *using*. An
authenticated CLI (`gh`, `vercel`, `supabase`, `firebase`) does the work without
the credential ever being read out. That covers most of what "grab the API key"
actually means in practice.

Full detail: [`docs/limits.md`](docs/limits.md).

---

## Uninstall

```bash
claude-autonomous off
rm -rf ~/.claude/skills/autonomous ~/.local/bin/claude-autonomous
```

Backups of every settings.json this tool touched stay in `~/.claude/backups/`.

---

## License

MIT
