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

**Windows** — PowerShell 7+ (not "Windows PowerShell"), no administrator rights

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
claude-autonomous doctor   # settings + toolchain + OS permissions
claude-autonomous off      # put everything back
```

### Platform support, and how each row was verified

There are two implementations of the same tool: `bin/claude-autonomous` (bash)
and `bin/claude-autonomous.ps1` (PowerShell). They write the same settings and
recognise each other's work — the test suite asserts that a mode toggled by one
is seen by the other.

| | Status | Secrets | Verified |
| --- | --- | --- | --- |
| **macOS** | full | Keychain | 39/39 PowerShell suite + bash suite, on 26.5. A real API key stored and used against a live endpoint |
| **Linux** | full | `secret-tool` | 39/39 PowerShell suite + bash suite, in a Debian 12 container with a session D-Bus and unlocked keyring |
| **Windows** | full | DPAPI | Everything except the DPAPI call itself: the suite asserts the Windows hook shape from any host. See below |

**What "except DPAPI" means.** Secrets on Windows are encrypted with
`ConvertFrom-SecureString`, which ties them to your Windows user account — no
key file exists to copy elsewhere. That call only runs on Windows, so it is the
one thing here not covered by a test run. Everything else on the Windows path —
argument parsing, the JSON merge, on/off/status/doctor, the `cmd.exe /c echo`
hook shape — is exercised by the same suite that passes on macOS and Linux.

Requirements: `python3` for the bash script, PowerShell 7+ for the PowerShell
one. On Windows, "Windows PowerShell" 5.1 is not enough and the installer says
so before touching any file.

```bash
pwsh tests/test.ps1                                   # any platform
dbus-run-session -- tests/linux-in-container.sh --with-pwsh   # in a Linux container
```

---

## Getting keys in without anyone typing

The usual advice is "store your key first". That is backwards — the key is
almost always already on the machine.

```bash
claude-autonomous harvest            # what is there: names, lengths, file paths
claude-autonomous harvest --apply    # move it into the keychain
```

`harvest` walks `.env` files under your project directories, shell profiles,
and the config files CLIs write, keeps only what actually looks like a
credential, and imports it. It prints names and byte counts, never values, and
skips public identifiers — `AUTH_DOMAIN` is a hostname, `CLIENT_ID` is public
by design. Moving those values out of plaintext files into the OS keychain is a
security improvement on its own.

For a key that exists nowhere yet, there are two paths that still avoid typing
a command:

```bash
pbpaste | claude-autonomous secret import GROQ_API_KEY   # from a dashboard's copy button
claude-autonomous vault                                  # a local page: paste one, or a whole .env
```

`vault` binds loopback only, requires a per-run token, rejects a forged `Host`
header, and closes itself after 15 idle minutes. It exists so that handing over
a key is a paste rather than a remembered command — not so that anything can
sign in on your behalf.

---

## Credentials, without handing them over

The request behind "let it grab the API key and do everything" is real, and it
does not require the agent to ever hold the key. Store it once, in your own
keychain, in your own terminal:

```bash
claude-autonomous secret set STRIPE_KEY     # hidden input, straight to keychain
```

Or, when the key is already on screen in a dashboard you are signed in to, let
the agent take it from there — click the page's copy button, then:

```bash
pbpaste | claude-autonomous secret import GROQ_API_KEY
```

Clipboard → keychain, without the value being read into the model's context, so
it never lands in a transcript. This is the route to prefer: reading a key off
the page with a screenshot puts the secret in the conversation permanently.

From then on the agent can use it freely:

```bash
claude-autonomous run STRIPE_KEY -- ./deploy.sh
claude-autonomous run AWS_KEY,AWS_SECRET -- python job.py
```

The value is exported into the child process. It is not in `argv`, not in
`stdout`, not in the transcript, and `secret list` prints names only. Backed by
the macOS Keychain, or `secret-tool` on Linux.

Most of the time you will not even need this — `gh`, `vercel`, `supabase`,
`firebase`, `aws` and `docker` carry their own auth, and an agent can just use
them.

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

Not asking is only half of "does it without me". The other half is finishing
without me, and being reachable while it happens:

| Setting | Effect |
| --- | --- |
| `doneMeansMerged: true` | Work continues to a mergeable PR, an armed cron, or a self-contained next step — not to a status update |
| `effortLevel: high` | Unattended work has nobody to catch a cheap wrong turn |
| `remoteControlAtStartup: true` | Drive the session from your phone |
| `autoUploadSessions: true` | Sessions readable from claude.ai |
| `agentPushNotifEnabled`, `inputNeededNotifEnabled` | If something truly needs you, it reaches you instead of waiting |
| `crossSessionInbound: accept` | Your other sessions can hand this one work |
| `autoMemoryEnabled: true` | Decisions survive past the session |

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

### The one prompt that survives

Claude Code hard-refuses to auto-approve an `rm` whose target is a critical
system path, or the session's working directory, an additional working
directory, or a parent of either. Its own wording:

> This requires explicit approval and cannot be auto-allowed by permission rules.

Not by `bypassPermissions`, not by an allow rule, not by the hook. It is
compiled in, and it is the correct call — an agent with every prompt suppressed
should still not be one keystroke from deleting the tree it is working in.

Nearly every occurrence is deleting the folder you are standing in, so the
installed skill teaches the shape that avoids it: step outside first
(`cd /tmp && rm -rf /path/to/workdir`) or empty the directory instead of
removing it.

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
