#!/usr/bin/env python3
"""Local vault UI for claude-autonomous.

A one-page app on 127.0.0.1 where you paste a secret — or a whole .env — and it
goes straight into the OS keychain. The agent then uses it through
`claude-autonomous run NAME -- ...` without the value ever passing through a
conversation.

What this deliberately is not: it does not hold account passwords, drive login
forms, or authenticate as anyone. It stores API keys and tokens you already
have, so that handing one over stops being a terminal command you must recall.

Stdlib only. Binds loopback, requires a per-run token, validates the Host
header, and exits on idle.
"""

from __future__ import annotations

import http.server
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import webbrowser

CLI = os.environ.get("CLAUDE_AUTONOMOUS_CLI") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "claude-autonomous"
)
TOKEN = secrets.token_urlsafe(24)
IDLE_TIMEOUT = 15 * 60
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

_last_seen = time.time()
_lock = threading.Lock()


def touch() -> None:
    global _last_seen
    with _lock:
        _last_seen = time.time()


def cli(*args: str, stdin: str | None = None) -> tuple[int, str]:
    """Run the CLI. Values travel on stdin, never in argv."""
    p = subprocess.run(
        [CLI, *args],
        input=stdin,
        capture_output=True,
        text=True,
    )
    return p.returncode, (p.stdout + p.stderr).strip()


def store(name: str, value: str) -> tuple[bool, str]:
    if not NAME_RE.match(name):
        return False, "name must look like an environment variable"
    if not value.strip():
        return False, "empty value"
    code, out = cli("secret", "import", name, stdin=value)
    # Never echo the value back, even on failure.
    return code == 0, out if code else f"stored {name} ({len(value.strip())} characters)"


def parse_env(text: str) -> list[tuple[str, str]]:
    """Accept .env, `export A=b`, and `A: b` shapes. Values are never logged."""
    out: list[tuple[str, str]] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        line = line.removeprefix("export ").strip()
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*[:=]\s*(.*)$", line)
        if not m:
            continue
        name, value = m.group(1), m.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value:
            out.append((name, value))
    return out


PAGE = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cofre — claude-autonomous</title>
<style>
:root{--bg:#16150f;--fg:#eae6dd;--muted:#948d80;--line:#2e2b23;--card:#1d1c15;
      --accent:#e08a4e;--ok:#6fbf73;--bad:#e0625e;--code:#22201a}
@media(prefers-color-scheme:light){:root{--bg:#fbfaf8;--fg:#1a1815;--muted:#6b655c;
      --line:#e2ded6;--card:#fff;--accent:#b4521f;--code:#f2efe9}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
     font:15px/1.6 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif}
.wrap{max-width:44rem;margin:0 auto;padding:2.5rem 1.25rem 4rem}
h1{font-size:1.6rem;margin:0 0 .3rem;letter-spacing:-.02em}
.sub{color:var(--muted);margin:0 0 2rem}
h2{font-size:1rem;margin:2rem 0 .6rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:1.1rem}
label{display:block;font-size:.85rem;color:var(--muted);margin:0 0 .3rem}
input,textarea{width:100%;background:var(--code);color:var(--fg);border:1px solid var(--line);
  border-radius:7px;padding:.6rem .7rem;font:14px ui-monospace,SFMono-Regular,Menlo,monospace}
textarea{min-height:8.5rem;resize:vertical}
.row{display:flex;gap:.6rem;margin-top:.7rem;align-items:center;flex-wrap:wrap}
button{background:var(--accent);color:#fff;border:0;border-radius:7px;
  padding:.55rem 1rem;font:600 14px system-ui;cursor:pointer}
button.ghost{background:transparent;color:var(--muted);border:1px solid var(--line)}
button:disabled{opacity:.5;cursor:default}
.msg{margin-top:.7rem;font-size:.9rem;min-height:1.3em}
.ok{color:var(--ok)} .bad{color:var(--bad)}
ul{list-style:none;padding:0;margin:.4rem 0 0}
li{display:flex;justify-content:space-between;align-items:center;
   padding:.5rem .1rem;border-bottom:1px solid var(--line);font-family:ui-monospace,Menlo,monospace;font-size:14px}
li:last-child{border-bottom:0}
li button{background:transparent;color:var(--muted);border:1px solid var(--line);padding:.2rem .55rem;font-size:12px}
.hint{color:var(--muted);font-size:.85rem;margin-top:.5rem}
code{background:var(--code);padding:.1em .35em;border-radius:4px;font-size:.9em}
</style></head><body><div class="wrap">

<h1>Cofre</h1>
<p class="sub">O valor vai direto para o chaveiro do sistema. Ele não passa pela
conversa, não vai para o transcript, e a lista abaixo nunca mostra o conteúdo.</p>

<h2>Guardar uma chave</h2>
<div class="card">
  <label for="n">Nome</label>
  <input id="n" placeholder="GROQ_API_KEY" autocomplete="off" spellcheck="false">
  <div style="margin-top:.7rem"></div>
  <label for="v">Valor</label>
  <input id="v" type="password" placeholder="cole aqui" autocomplete="off">
  <div class="row">
    <button id="save">Guardar</button>
    <button class="ghost" id="peek" type="button">Mostrar valor</button>
  </div>
  <div class="msg" id="m1"></div>
</div>

<h2>Ou colar um .env inteiro</h2>
<div class="card">
  <label for="e">Uma chave por linha. Aceita <code>A=b</code>, <code>export A=b</code> e <code>A: b</code>.</label>
  <textarea id="e" placeholder="GROQ_API_KEY=gsk_...&#10;STRIPE_KEY=sk_live_..." spellcheck="false"></textarea>
  <div class="row"><button id="imp">Importar todas</button></div>
  <div class="msg" id="m2"></div>
</div>

<h2>Guardadas</h2>
<div class="card"><ul id="list"></ul>
  <p class="hint">Use com <code>claude-autonomous run NOME -- seu-comando</code>.</p>
</div>

<div class="row" style="margin-top:2rem">
  <button class="ghost" id="quit">Fechar o cofre</button>
  <span class="hint" id="idle"></span>
</div>

<script>
const T = new URLSearchParams(location.search).get('t') || '';
const api = (path, body) => fetch(path + '?t=' + encodeURIComponent(T), {
  method: 'POST', headers: {'Content-Type': 'application/json'},
  body: JSON.stringify(body || {})
}).then(r => r.json());
const say = (el, ok, text) => { el.className = 'msg ' + (ok ? 'ok' : 'bad'); el.textContent = text; };

async function refresh() {
  const r = await api('/list');
  const ul = document.getElementById('list');
  ul.innerHTML = '';
  if (!r.names.length) { ul.innerHTML = '<li style="color:var(--muted);font-family:inherit">nada guardado ainda</li>'; return; }
  for (const n of r.names) {
    const li = document.createElement('li');
    li.textContent = n;
    const b = document.createElement('button');
    b.textContent = 'remover';
    b.onclick = async () => { await api('/delete', {name: n}); refresh(); };
    li.appendChild(b);
    ul.appendChild(li);
  }
}

document.getElementById('peek').onclick = () => {
  const v = document.getElementById('v');
  v.type = v.type === 'password' ? 'text' : 'password';
};

document.getElementById('save').onclick = async () => {
  const n = document.getElementById('n').value.trim();
  const v = document.getElementById('v').value;
  const m = document.getElementById('m1');
  if (!n || !v) { say(m, false, 'preencha nome e valor'); return; }
  const r = await api('/add', {name: n, value: v});
  say(m, r.ok, r.message);
  if (r.ok) { document.getElementById('n').value = ''; document.getElementById('v').value = ''; refresh(); }
};

document.getElementById('imp').onclick = async () => {
  const t = document.getElementById('e').value;
  const m = document.getElementById('m2');
  if (!t.trim()) { say(m, false, 'cole algo primeiro'); return; }
  const r = await api('/import', {text: t});
  say(m, r.ok, r.message);
  if (r.ok) { document.getElementById('e').value = ''; refresh(); }
};

document.getElementById('quit').onclick = async () => {
  await api('/quit');
  document.body.innerHTML = '<div class="wrap"><h1>Cofre fechado</h1>' +
    '<p class="sub">Pode fechar esta aba.</p></div>';
};

refresh();
setInterval(() => api('/ping'), 60000);
</script>
</div></body></html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "claude-autonomous-vault"

    def log_message(self, *a):  # never log request bodies or paths with tokens
        pass

    def _host_ok(self) -> bool:
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("127.0.0.1", "localhost", "[::1]", "::1")

    def _token_ok(self) -> bool:
        _, _, query = self.path.partition("?")
        for part in query.split("&"):
            if part.startswith("t="):
                from urllib.parse import unquote
                return secrets.compare_digest(unquote(part[2:]), TOKEN)
        return False

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj: dict, code: int = 200) -> None:
        self._send(code, json.dumps(obj).encode(), "application/json")

    def do_GET(self):
        if not self._host_ok():
            self._send(400, b"bad host", "text/plain")
            return
        if self.path.split("?")[0] != "/" or not self._token_ok():
            self._send(404, b"not found", "text/plain")
            return
        touch()
        self._send(200, PAGE.encode(), "text/html; charset=utf-8")

    def do_POST(self):
        if not self._host_ok() or not self._token_ok():
            self._json({"ok": False, "message": "unauthorised"}, 403)
            return
        touch()
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length") or 0)
        if length > 1_000_000:
            self._json({"ok": False, "message": "too large"}, 413)
            return
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json({"ok": False, "message": "bad request"}, 400)
            return

        if path == "/ping":
            self._json({"ok": True})
        elif path == "/list":
            code, out = cli("secret", "list")
            names = [ln.strip() for ln in out.splitlines()
                     if ln.startswith("  ") and ln.strip()]
            self._json({"ok": code == 0, "names": names})
        elif path == "/add":
            ok, msg = store(str(payload.get("name", "")), str(payload.get("value", "")))
            self._json({"ok": ok, "message": msg})
        elif path == "/import":
            pairs = parse_env(str(payload.get("text", "")))
            if not pairs:
                self._json({"ok": False, "message": "nenhuma linha NOME=valor reconhecida"})
                return
            done, failed = [], []
            for name, value in pairs:
                ok, _ = store(name, value)
                (done if ok else failed).append(name)
            msg = f"{len(done)} guardada(s): {', '.join(done)}" if done else ""
            if failed:
                msg += (" — falharam: " if msg else "falharam: ") + ", ".join(failed)
            self._json({"ok": bool(done), "message": msg})
        elif path == "/delete":
            name = str(payload.get("name", ""))
            if not NAME_RE.match(name):
                self._json({"ok": False, "message": "invalid name"}, 400)
                return
            code, _ = cli("secret", "rm", name)
            self._json({"ok": code == 0})
        elif path == "/quit":
            self._json({"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            self._json({"ok": False, "message": "not found"}, 404)


def main() -> int:
    if not os.path.exists(CLI):
        print(f"cannot find the CLI at {CLI}", file=sys.stderr)
        return 1

    port = 0
    for i, a in enumerate(sys.argv):
        if a == "--port" and i + 1 < len(sys.argv):
            port = int(sys.argv[i + 1])

    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.daemon_threads = True
    real_port = httpd.socket.getsockname()[1]
    url = f"http://127.0.0.1:{real_port}/?t={TOKEN}"

    def reaper():
        while True:
            time.sleep(20)
            with _lock:
                idle = time.time() - _last_seen
            if idle > IDLE_TIMEOUT:
                httpd.shutdown()
                return

    threading.Thread(target=reaper, daemon=True).start()

    # flush=True: stdout is block-buffered when redirected, and a vault whose
    # URL never appears is a vault nobody can open.
    print("Cofre aberto em:", flush=True)
    print(f"  {url}", flush=True)
    print(flush=True)
    print("Loopback apenas, token de uso unico, fecha sozinho apos 15 min parado.",
          flush=True)
    if "--no-open" not in sys.argv:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Cofre fechado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
