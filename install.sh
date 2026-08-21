#!/usr/bin/env bash
# claude-autonomous installer — macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.sh | bash
#
# Installs the `claude-autonomous` command and the `autonomous` skill, then
# turns the mode on. Nothing is overwritten without a backup first.
set -euo pipefail

REPO="NspxMiguel/claude-autonomous"
RAW="https://raw.githubusercontent.com/$REPO/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILL_DIR="$CLAUDE_DIR/skills/autonomous"
BIN_DIR="$HOME/.local/bin"

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 is required (it does the JSON merge)."

# Run from a clone if we are in one, otherwise fetch.
SRC=""
if [ -f "$(dirname "${BASH_SOURCE[0]:-}")/bin/claude-autonomous" ] 2>/dev/null; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() { # fetch <repo-relative-path> <destination>
  if [ -n "$SRC" ]; then
    cp "$SRC/$1" "$2"
  else
    curl -fsSL "$RAW/$1" -o "$2" || die "could not download $1"
  fi
}

say "claude-autonomous"
say "=================="
say ""

mkdir -p "$BIN_DIR" "$SKILL_DIR"

say "-> installing the command in $BIN_DIR"
fetch bin/claude-autonomous "$BIN_DIR/claude-autonomous"
chmod +x "$BIN_DIR/claude-autonomous"
# The helpers must sit next to the CLI: it locates them relative to itself.
fetch bin/harvest.py "$BIN_DIR/harvest.py"
fetch bin/vault.py   "$BIN_DIR/vault.py"
fetch bin/import_csv.py "$BIN_DIR/import_csv.py"

say "-> installing the skill in $SKILL_DIR"
fetch skill/SKILL.md "$SKILL_DIR/SKILL.md"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    say ""
    say "   note: $BIN_DIR is not on your PATH. Add this to your shell profile:"
    say "     export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

say ""
say "-> applying the settings"
"$BIN_DIR/claude-autonomous" on

say ""
"$BIN_DIR/claude-autonomous" status || true

cat <<'EOF'

Two things the installer cannot do for you:

  1. Restart your Claude Code session. The permission mode is read at startup.

  2. Grant the operating system permissions, once, when first used.
     macOS: System Settings -> Privacy & Security -> Screen Recording,
            Accessibility, Automation, Files and Folders.
     Linux: nothing needed for the shell; a Wayland session will still gate
            screen capture through its own portal.

To undo everything:  claude-autonomous off
What it changed:     https://github.com/NspxMiguel/claude-autonomous#what-it-changes
EOF
