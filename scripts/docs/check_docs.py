#!/usr/bin/env python3
"""Cross-document consistency checks for PRD/SDD/QA/ADR/evidence ledger.

Checks: every FR/NFR has test cases (QA §14), every TC id is defined once, every referenced FR/NFR/TC/ADR/evidence id exists,
every US has a Gherkin AT, and every relative Markdown link resolves.
Usage: python3 scripts/docs/check_docs.py <repo-root>   (exit 0 = no problems)
"""
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); docs = root/"docs"
read = lambda p: p.read_text(encoding="utf-8")
prd, sdd, qa, ev = read(docs/"PRD.md"), read(docs/"SDD.md"), read(docs/"QA_SUITE.md"), read(docs/"research/RESEARCH_EVIDENCE.md")
adr_dir = docs/"adr"; adrs = {p.name[:4] for p in adr_dir.glob("[0-9][0-9][0-9][0-9]-*.md")}
all_md = {p: read(p) for p in root.rglob("*.md") if ".claude" not in p.parts and "node_modules" not in p.parts}
problems = []
# 1. FR/NFR defined in PRD tables
fr_def = set(re.findall(r"^\| (FR-\d{2}) \|", prd, re.M)); nfr_def = set(re.findall(r"^\| (NFR-[A-Z]+\d{2}) \|", prd, re.M))
req_def = fr_def | nfr_def
# 2. TC defined in QA tables
tc_def = set(re.findall(r"^\| (TC-[A-Z]+-\d{2}) \|", qa, re.M))
# 2b. a TC id is defined at most once in the test-case tables (result rows in §11 have 3 columns)
tc_rows = [m.group(1) for m in re.finditer(r"^\| (TC-[A-Z]+-\d{2}) \|(.*)$", qa, re.M) if m.group(2).count("|") >= 4]
for t in sorted({t for t in tc_rows if tc_rows.count(t) > 1}): problems.append(f"[dup] {t} defined more than once in QA test-case tables")
# 3. traceability matrix
mx = qa[qa.index("## 14. Matriks traceability"):]
matrix = {}
for req, tcs in re.findall(r"^\| ((?:FR|NFR)-[A-Z]*\d{2}) \| (.+?) \|$", mx, re.M):
    matrix[req] = set(re.findall(r"TC-[A-Z]+-\d{2}", tcs))
for r in sorted(req_def - set(matrix)): problems.append(f"[trace] {r} has no test cases in QA §14")
for r, tcs in matrix.items():
    if r not in req_def: problems.append(f"[trace] matrix row {r} not defined in PRD")
    for t in tcs - tc_def: problems.append(f"[trace] {r} -> {t} not defined in QA")
orphans = tc_def - set().union(*matrix.values())
# 4. referenced FR/NFR/TC everywhere
for p, t in all_md.items():
    rel = p.relative_to(root)
    for m in set(re.findall(r"\b(?:FR|NFR)-[A-Z]*\d{2}\b", t)):
        if m not in req_def: problems.append(f"[ref] {rel}: {m} undefined")
    for m in set(re.findall(r"\bTC-[A-Z]+-\d{2}\b", t)):
        if m not in tc_def: problems.append(f"[ref] {rel}: {m} undefined")
    for m in set(re.findall(r"\bADR-(\d{4})\b", t)):
        if m not in adrs: problems.append(f"[ref] {rel}: ADR-{m} missing file")
    for m in set(re.findall(r"\bADR-(\d{3})\b(?!\d)", t)):
        problems.append(f"[ref] {rel}: old-style ADR-{m}")
# 5. evidence ids
ev_def = set(re.findall(r"^\| (E\d{2}) \|", ev, re.M)) | set(re.findall(r"^\| (O-[A-Z]\d{2}) \|", ev, re.M)) | set(re.findall(r"^\| (I-\d{2}) \|", ev, re.M)) | set(re.findall(r"^\| (U\d{2}) \|", ev, re.M))
def expand(t):
    out=set(re.findall(r"\b(E\d{2}|O-[A-Z]\d{2}|I-\d{2}|U\d{2})\b", t))
    for a,b in re.findall(r"\b(O-[A-Z]\d{2})[–-](O-[A-Z]\d{2})\b", t):
        pre=a[:3]; 
        for n in range(int(a[3:]), int(b[3:])+1): out.add(f"{pre}{n:02d}")
    return out
for p, t in all_md.items():
    rel = p.relative_to(root)
    for m in expand(t) - ev_def:
        problems.append(f"[evidence] {rel}: {m} undefined in ledger")
# 6. US/AT
us = set(re.findall(r"^\| (US-\d{2}) \|", prd, re.M)); at = set(re.findall(r"# (AT-\d{2}) ↔ (US-\d{2})", qa))
at_us = {u for _, u in at}
for u in sorted(us - at_us): problems.append(f"[accept] {u} has no Gherkin AT")
# 7. relative links
for p, t in all_md.items():
    for link in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", t):
        if link.startswith(("http", "mailto:")): continue
        if not (p.parent/link).exists(): problems.append(f"[link] {p.relative_to(root)} -> {link} missing")
print(f"FR={len(fr_def)} NFR={len(nfr_def)} TC={len(tc_def)} matrix_rows={len(matrix)} ADR files={len(adrs)} evidence ids={len(ev_def)} US={len(us)} AT={len(at)}")
covered = {r for r in req_def if matrix.get(r)}
print(f"requirements_defined={len(req_def)} requirements_with_tests={len(covered)} requirements_without_tests={len(req_def - covered)}")
adr_files = sorted(adr_dir.glob("[0-9][0-9][0-9][0-9]-*.md"))
adr_jev = [f.name for f in adr_files if "Catatan keputusan JEV" in read(f)]
print(f"adr_total={len(adr_files)} adr_with_jev_decision_record={len(adr_jev)} adr_evidence_based={len(adr_files) - len(adr_jev)}")
print(f"orphan TCs (not in matrix, informational): {sorted(orphans)}")
print("\n".join(sorted(set(problems))) or "NO PROBLEMS")
print(f"problems: {len(set(problems))}")
sys.exit(1 if problems else 0)
