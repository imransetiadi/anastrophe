#!/usr/bin/env python3
"""Render every ```mermaid block in the repo's Markdown to verify it parses.

Usage: python3 scripts/docs/check_mermaid.py <repo-root> <out-dir> <mmdc-path> <puppeteer-config.json>
  mmdc: install with `npm install @mermaid-js/mermaid-cli@11.4.0` (set PUPPETEER_SKIP_DOWNLOAD=true
  and point puppeteer-config.json's executablePath at a local Chrome to avoid downloading Chromium).
"""
import re, subprocess, sys, pathlib
root = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2]); mmdc = sys.argv[3]; cfg = sys.argv[4]
files = [p for p in root.rglob("*.md") if ".claude" not in p.parts and "node_modules" not in p.parts]
total = fails = 0
for f in sorted(files):
    text = f.read_text(encoding="utf-8")
    for i, m in enumerate(re.finditer(r"```mermaid\n(.*?)```", text, re.S)):
        total += 1
        src = out / f"{f.stem}_{i}.mmd"; src.write_text(m.group(1), encoding="utf-8")
        svg = out / f"{f.stem}_{i}.svg"
        r = subprocess.run([mmdc, "-i", str(src), "-o", str(svg), "-p", cfg, "-q"], capture_output=True, text=True, timeout=120)
        ok = r.returncode == 0 and svg.exists() and svg.stat().st_size > 0
        if not ok:
            fails += 1
            print(f"FAIL {f.relative_to(root)} #{i}: {(r.stderr or r.stdout).strip()[:600]}")
        else:
            print(f"ok   {f.relative_to(root)} #{i}")
print(f"\n{total - fails}/{total} diagrams render OK")
sys.exit(1 if fails else 0)
