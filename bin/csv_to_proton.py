#!/usr/bin/env python3
"""Seed a Proton Pass vault from a password-manager CSV export.

This is the one automatable direction. A live, two-way Apple<->Proton sync
cannot be built: the Apple Passwords store is closed on both ends — nothing
reads it without the app plus Touch ID per item, and CLI writes land in the
legacy login keychain that the Passwords app never reads. Proton, by contrast,
is fully scriptable. So the realistic flow is one-way and point-in-time:

    Apple Passwords  ->  (File > Export All Passwords, Touch ID)  ->  CSV
    CSV              ->  this tool  ->  pass-cli item create login  ->  Proton

It is a copy at a moment, not a mirror. To go the other way, export from Proton
and import that CSV into the Passwords app by hand.

Values never appear in argv (they would show up in `ps`): each item is built as
JSON and piped to `pass-cli item create login --from-template -`. The template
is fetched from pass-cli at runtime, so this adapts to the real item schema
rather than guessing it.

    claude-autonomous proton-seed export.csv --vault Dev            # preview
    claude-autonomous proton-seed export.csv --vault Dev --apply
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path

PASS = os.environ.get("PASS_CLI") or "pass-cli"

COL = {
    "title": ("title", "name"),
    "url": ("url", "website", "urls"),
    "user": ("username", "user", "login"),
    "email": ("email",),
    "password": ("password", "pass"),
}


def have_session() -> bool:
    try:
        return subprocess.run([PASS, "info"], capture_output=True).returncode == 0
    except FileNotFoundError:
        sys.exit("pass-cli is not installed. Install it (proton.me/pass) and log in.")


def get_template() -> dict | None:
    p = subprocess.run([PASS, "item", "create", "login", "--get-template"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return None


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
        rows = []
        for r in reader:
            def g(k):
                return (r.get(lut.get(k, ""), "") or "").strip()
            if g("password"):
                rows.append({"title": g("title"), "url": g("url"),
                             "user": g("user"), "email": g("email"),
                             "password": r.get(lut["password"], "")})
        return rows


def fill(template: dict, row: dict) -> dict:
    """Populate a copy of the fetched template. Shapes vary between pass-cli
    versions, so set fields wherever they plausibly live."""
    t = json.loads(json.dumps(template))  # deep copy

    def put(container, keys, value):
        if not value:
            return
        for k in keys:
            if isinstance(container, dict) and k in container:
                container[k] = value
                return

    put(t, ("title", "name"), row["title"] or row["url"] or row["user"] or "Imported")
    content = t.get("content") if isinstance(t.get("content"), dict) else t
    put(content, ("username",), row["user"])
    put(content, ("email",), row["email"])
    put(content, ("password",), row["password"])
    urls = row["url"]
    if urls:
        for holder in (content, t):
            if isinstance(holder, dict) and "urls" in holder and isinstance(holder["urls"], list):
                holder["urls"] = [urls]
                break
    return t


def create(item: dict, vault: str | None) -> bool:
    cmd = [PASS, "item", "create", "login", "--from-template", "-"]
    if vault:
        cmd[-2:-2] = ["--vault-name", vault]
    p = subprocess.run(cmd, input=json.dumps(item), capture_output=True, text=True)
    return p.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", type=Path)
    ap.add_argument("--vault", help="target Proton vault name")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if not args.csv.is_file():
        sys.exit(f"no such file: {args.csv}")

    rows = read_rows(args.csv)
    if not rows:
        print("no rows with a password in that CSV")
        return 0

    print(f"{len(rows)} entradas com senha no CSV -> cofre Proton "
          f"'{args.vault or '(padrão)'}'")
    width = max((len(r["title"] or r["url"] or r["user"] or "?") for r in rows), default=8)
    for r in rows[:60]:
        label = r["title"] or r["url"] or r["user"] or "?"
        print(f"  {label[:width].ljust(width)}  {len(r['password']):>4} chars")
    if len(rows) > 60:
        print(f"  ... e mais {len(rows) - 60}")

    if not args.apply:
        print(f"\nEscreve no Proton com:  claude-autonomous proton-seed {args.csv} "
              f"{'--vault ' + args.vault + ' ' if args.vault else ''}--apply")
        print("Isto é cópia num instante, não sync. Apague o CSV depois.")
        return 0

    if not have_session():
        sys.exit("no Proton session — run `pass-cli login` first (that is yours to do)")

    template = get_template()
    if template is None:
        sys.exit("could not fetch the item template from pass-cli")

    ok = 0
    print()
    for r in rows:
        if create(fill(template, r), args.vault):
            ok += 1
        else:
            print(f"  falhou: {(r['title'] or r['url'] or '?')[:40]}")
    print(f"{ok}/{len(rows)} criada(s) no Proton")
    print("A partir daqui eu leio com:  pass-cli run -- seu-comando")
    return 0


if __name__ == "__main__":
    sys.exit(main())
