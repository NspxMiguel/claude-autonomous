#!/usr/bin/env python3
"""Import an Apple Passwords (or any) CSV export into the keychain.

The manual half of "both worlds". macOS will not let anything bulk-read the
Passwords app store — that vault (keychain-2.db) needs the app plus Touch ID per
item, and there is no export CLI. What the app *does* offer is
File -> Export All Passwords..., gated by Touch ID, which writes a CSV. This
reads that CSV.

Apple's columns are: Title,URL,Username,Password,Notes,OTPAuth. Other managers
(1Password, Bitwarden, Chrome) export similar shapes; the header is matched by
name, so those work too.

Values are never printed. The CSV is plaintext on disk, so this offers to shred
it when done, and says so loudly if you decline.

A website login password cannot drive autonomous work — `run` injects into shell
commands, and logging into a site as you stays off-limits. So by default this
imports only entries that look like developer credentials (API tokens, long
opaque secrets); pass --all to take everything, --sites to take website logins
too. Nothing is imported without --apply.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from pathlib import Path

CLI = os.environ.get("CLAUDE_AUTONOMOUS_CLI") or str(
    Path(__file__).resolve().parent / "claude-autonomous"
)

# Header aliases across the common exporters.
COL = {
    "title": ("title", "name"),
    "url": ("url", "website", "urls"),
    "user": ("username", "user", "login", "email"),
    "password": ("password", "pass"),
}

DEV_HOST = re.compile(
    r"(api\.|console\.|dashboard\.|developer\.|platform\.|"
    r"github|gitlab|vercel|netlify|supabase|firebase|cloudflare|aws|"
    r"openai|anthropic|groq|stripe|twilio|sendgrid|ngrok|railway|render|fly\.io|"
    r"heroku|digitalocean|hetzner|npmjs|pypi|docker|huggingface)", re.I
)
DEV_TITLE = re.compile(r"(api|token|key|secret|deploy|ci|webhook|service.?account)", re.I)
# A developer secret tends to be long and opaque; a human password rarely is.
OPAQUE = re.compile(r"^[A-Za-z0-9._\-]{24,}$")

SLUG = re.compile(r"[^A-Za-z0-9]+")


def slugify(title: str, url: str, user: str) -> str:
    base = title.strip() or url.strip() or user.strip() or "SECRET"
    # Prefer the registrable host when the title is just a URL.
    m = re.search(r"https?://([^/]+)", base)
    if m:
        base = m.group(1)
    base = base.split("//")[-1]
    name = SLUG.sub("_", base).strip("_").upper()
    if user.strip():
        u = SLUG.sub("_", user.split("@")[0]).strip("_").upper()
        if u and u not in name:
            name = f"{name}_{u}"
    if not name or not name[0].isalpha() and name[0] != "_":
        name = "K_" + name
    return name[:64] or "SECRET"


def classify(title: str, url: str, password: str) -> str:
    """'dev' for API-token-shaped, 'site' for a website login."""
    if DEV_HOST.search(url) or DEV_TITLE.search(title) or OPAQUE.match(password):
        return "dev"
    return "site"


def read_rows(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return []
        lut = {}
        for canon, aliases in COL.items():
            for field in reader.fieldnames:
                if field.strip().lower() in aliases:
                    lut[canon] = field
                    break
        if "password" not in lut:
            sys.exit("this CSV has no recognisable Password column")
        out = []
        for row in reader:
            out.append({
                "title": (row.get(lut.get("title", ""), "") or "").strip(),
                "url": (row.get(lut.get("url", ""), "") or "").strip(),
                "user": (row.get(lut.get("user", ""), "") or "").strip(),
                "password": row.get(lut["password"], "") or "",
            })
        return out


def store(name: str, value: str) -> bool:
    p = subprocess.run([CLI, "secret", "import", name], input=value,
                       capture_output=True, text=True)
    return p.returncode == 0


def shred(path: Path) -> None:
    # Overwrite before unlinking; a plaintext password dump should not linger in
    # free space to be undeleted.
    try:
        size = path.stat().st_size
        with path.open("r+b") as f:
            f.write(os.urandom(min(size, 4_000_000)))
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass
    try:
        path.unlink()
    except OSError:
        pass


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("csv", type=Path)
    ap.add_argument("--apply", action="store_true", help="actually import")
    ap.add_argument("--all", action="store_true", help="import every row")
    ap.add_argument("--sites", action="store_true", help="include website logins")
    ap.add_argument("--rm-after", action="store_true", help="shred the CSV when done")
    args = ap.parse_args()

    if not args.csv.is_file():
        sys.exit(f"no such file: {args.csv}")

    rows = [r for r in read_rows(args.csv) if r["password"]]
    if not rows:
        print("no rows with a password in that CSV")
        return 0

    want_sites = args.all or args.sites
    chosen = []
    for r in rows:
        kind = classify(r["title"], r["url"], r["password"])
        if kind == "site" and not want_sites:
            continue
        chosen.append((slugify(r["title"], r["url"], r["user"]), r["password"], kind, r))

    dev = sum(1 for c in chosen if c[2] == "dev")
    site = sum(1 for c in chosen if c[2] == "site")
    skipped = len(rows) - len(chosen)

    print(f"{len(rows)} entradas no CSV — {dev} parecem credencial de dev, "
          f"{site} são login de site, {skipped} ignoradas")
    if skipped and not want_sites:
        print("  (logins de site ficam de fora por padrão; --sites ou --all inclui)")
    print()

    width = max((len(c[0]) for c in chosen), default=10)
    for name, value, kind, _ in chosen[:60]:
        tag = "dev " if kind == "dev" else "site"
        act = "importa" if args.apply else "seria"
        print(f"  {name.ljust(width)}  {len(value):>4} chars  {tag}  {act}")
    if len(chosen) > 60:
        print(f"  ... e mais {len(chosen) - 60}")

    if not args.apply:
        print(f"\nPara importar:  claude-autonomous import-csv {args.csv} --apply")
        print("O CSV é texto puro — apague depois, ou use --rm-after.")
        return 0

    if not chosen:
        print("\nnada a importar com os filtros atuais")
        return 0

    ok = 0
    seen: dict[str, int] = {}
    print()
    for name, value, _kind, _ in chosen:
        # Disambiguate collisions rather than overwrite.
        if name in seen:
            seen[name] += 1
            name = f"{name}_{seen[name]}"
        else:
            seen[name] = 1
        if store(name, value):
            ok += 1
        else:
            print(f"  falhou {name}")
    print(f"{ok}/{len(chosen)} importada(s) no chaveiro")

    if args.rm_after:
        shred(args.csv)
        print(f"CSV apagado com sobrescrita: {args.csv}")
    else:
        print(f"\n!! O CSV ainda está em texto puro: {args.csv}")
        print("   Apague:  claude-autonomous import-csv --shred " + str(args.csv))
    return 0


if __name__ == "__main__":
    # allow a bare --shred FILE to wipe without importing
    if len(sys.argv) == 3 and sys.argv[1] == "--shred":
        target = Path(sys.argv[2])
        shred(target)
        print(f"apagado com sobrescrita: {target}")
        sys.exit(0)
    sys.exit(main())
