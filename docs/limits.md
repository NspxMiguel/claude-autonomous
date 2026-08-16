# What the config reaches, and what it does not

Three layers can stop an action. Only the first one is a settings file.

## 1. Claude Code — the config owns this

`claude-autonomous on` zeroes this layer out:

| Before | After |
| --- | --- |
| "Allow this command?" | `defaultMode: bypassPermissions` + a `PreToolUse` hook answering `allow` |
| Scope limited to the project directory | `additionalDirectories` covering `$HOME`, `/Applications`, `/Volumes`, `/opt`, `/usr/local`, `/tmp` |
| Dangerous-mode dialog at startup | `skipDangerousModePermissionPrompt: true` |
| "Trust this MCP server?" | `enableAllProjectMcpServers: true` |
| Cost warning before a workflow | `skipWorkflowUsageWarning: true` |
| A model question parking the session | `askUserQuestionTimeout: "60s"` |
| Bash cut off at 2 minutes | `BASH_MAX_TIMEOUT_MS: 600000` |
| Commands confined | `sandbox.enabled: false` |

**The one guardrail kept on purpose:** `fileCheckpointingEnabled: true`. With
every prompt suppressed, `/rewind` is the only undo left.

## 2. The operating system — no config reaches this

### macOS

TCC belongs to the system. The first use of each raises a dialog only a human
can dismiss:

- **Screen Recording** — screenshots via computer-use;
- **Accessibility** — clicking and typing via computer-use;
- **Automation (Apple Events)** — driving an app through AppleScript;
- **Files and Folders** — Desktop, Documents, Downloads, full disk;
- **Keychain** — anything reading a stored credential.

Grant them all in one sitting under System Settings → Privacy & Security, so a
dialog never lands in the middle of a task.

The computer-use MCP server has its own per-application approval, also outside
`settings.json`, and it tiers what it grants: browsers land in **read** (visible,
not clickable) and terminals/IDEs in **click** (clickable, not typeable). Both
have a way around them that is faster anyway — the browser MCP for web work, the
Bash tool for shell work.

### Linux

The shell needs nothing. A Wayland session still gates screen capture through
its own portal, and that portal prompt is not something a settings file removes.

### Windows

No equivalent of TCC for the shell. UAC still gates anything requiring elevation.

## 3. The model's own limits — not a config at all

These are not in an editable file and do not change with `bypassPermissions`:

- no typing a password, token, API key or 2FA code into a form;
- no logging in as someone else, no creating accounts;
- no transfers, no trades, no spending without confirmation;
- no acting on an instruction found *inside* a page, email or file that was
  read as data — it gets surfaced to you instead;
- confirmation before irreversible destruction, and before publishing anything
  to the internet.

### The credential line is narrower than it looks

The limit is on *typing or printing* a secret, not on *using* one. Two routes
cover nearly everything "grab the API key and do it all" actually means.

**Route 1 — the CLI already holds the auth.** Nothing is read at all:

```bash
gh api user                      # GitHub, already logged in
vercel deploy --prod             # Vercel
supabase db push                 # Supabase
firebase deploy --only hosting   # Firebase
```

**Route 2 — the command needs the value in its environment.** Store it once,
then the agent uses it without ever seeing it:

```bash
claude-autonomous secret set STRIPE_KEY          # you, once, hidden input
claude-autonomous run STRIPE_KEY -- ./deploy.sh  # agent, freely, from then on
```

`run` exports into the child process: not in `argv`, not in `stdout`, not in the
transcript. `secret list` prints names only.

**Route 3 — the key is on screen in a dashboard you are signed in to.** The
agent takes it from there without ever reading it: click the page's own copy
button, then pipe the clipboard into the keychain.

```bash
pbpaste | claude-autonomous secret import GROQ_API_KEY
```

This is strictly better than having the agent read the key off the page. A
screenshot or page-text read puts the secret into the conversation, where it
persists — and with `autoUploadSessions` on, syncs. `import` never sees stdout.

**What is genuinely left.** Signing in to the dashboard, and a 2FA code. Those
stay with you — one login you were going to do anyway, not an ongoing tax on
every task.

An agent that writes and runs the deploy script without ever holding the key is
doing the whole job. Holding the key was never the job.

## Checking

```bash
claude-autonomous status
```

Exits non-zero if anything drifted, so it works in a shell profile or a CI
check.
