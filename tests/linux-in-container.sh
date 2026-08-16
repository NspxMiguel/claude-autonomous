#!/usr/bin/env bash
# Runs the full Linux suite inside a container, under a session D-Bus with an
# unlocked keyring. Invoke as:
#
#   dbus-run-session -- tests/linux-in-container.sh [--with-pwsh]
set -uo pipefail

# gnome-keyring needs a control socket before secret-tool will talk to it.
# --unlock reads the password from stdin and creates the keyring if absent.
eval "$(printf 'ca-test' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)"
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

echo "--- sanidade: o keyring aceita gravar e devolver? ---"
printf 'valor-sonda' | secret-tool store --label=sonda service ca-probe key p 2>/dev/null
got="$(secret-tool lookup service ca-probe key p 2>/dev/null)"
if [ "$got" = "valor-sonda" ]; then
  echo "    keyring OK"
else
  echo "    keyring INDISPONIVEL neste container — testes de segredo nao valem nada aqui"
  exit 3
fi
secret-tool clear service ca-probe key p 2>/dev/null

echo
echo "=== suite bash ==="
tests/linux-keyring.sh
bash_rc=$?

ps_rc=0
if [ "${1:-}" = "--with-pwsh" ] && command -v pwsh >/dev/null 2>&1; then
  echo
  echo "=== suite PowerShell ==="
  pwsh -NoLogo -NoProfile -File tests/test.ps1
  ps_rc=$?
fi

exit $(( bash_rc + ps_rc ))
