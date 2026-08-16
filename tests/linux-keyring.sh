#!/usr/bin/env bash
# Exercises the secret path on Linux against a real gnome-keyring.
# Run inside a container: dbus-run-session -- tests/linux-keyring.sh
set -uo pipefail

CA="$HOME/.local/bin/claude-autonomous"
NAME=CA_TEST_KEY
VALUE="gsk_linux_teste_1234567890"
fail=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FALHOU %s\n' "$1"; fail=$((fail+1)); }

printf '' | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1

printf '%s' "$VALUE" | "$CA" secret import "$NAME" >/dev/null 2>&1 \
  && ok "import gravou" || bad "import gravou"

"$CA" secret list 2>/dev/null | grep -q "$NAME" \
  && ok "list mostra o nome" || bad "list mostra o nome"

"$CA" secret list 2>/dev/null | grep -q "$VALUE" \
  && bad "list VAZOU o valor" || ok "list nao vaza o valor"

got="$("$CA" run "$NAME" -- sh -c 'printf "%s" "$CA_TEST_KEY"' 2>/dev/null)"
[ "$got" = "$VALUE" ] \
  && ok "run injetou o valor exato ($(printf '%s' "$got" | wc -c | tr -d ' ') chars)" \
  || bad "run injetou (recebeu ${#got} chars)"

"$CA" run "$NAME" -- sh -c 'exit 42' 2>/dev/null
[ $? -eq 42 ] && ok "run propaga exit code" || bad "run propaga exit code"

"$CA" secret rm "$NAME" >/dev/null 2>&1
"$CA" secret list 2>/dev/null | grep -q "$NAME" \
  && bad "rm apagou" || ok "rm apagou"

echo
[ $fail -eq 0 ] && echo "LINUX: todos os testes de segredo passaram" \
                || echo "LINUX: $fail falha(s)"
exit $fail
