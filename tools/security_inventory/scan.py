#!/usr/bin/env python3
"""
Static security inventory for aqar_user (no DB connection).
Outputs: out/inventory_report.md, out/inventory.json, out/inventory_summary.csv
"""
from __future__ import annotations

import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCAN_DIRS = [
    ROOT / "supabase" / "migrations",
    ROOT / "supabase" / "sql",
]
CODE_DIRS = [ROOT / "lib", ROOT / "web"]

SERVICE_ROLE_IN_LIB = re.compile(
    r"service_role|SERVICE_ROLE|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.",
    re.MULTILINE,
)
SUPABASE_KEY = re.compile(r"SUPABASE_(SERVICE_ROLE|SERVICE_KEY)", re.IGNORECASE)


def iter_sql_files() -> list[Path]:
    out: list[Path] = []
    for base in SCAN_DIRS:
        if not base.exists():
            continue
        out.extend(p for p in base.rglob("*.sql") if p.is_file())
    return sorted(out)


def scan_sql() -> dict:
    anon_hits: list[dict] = []
    line_pat = re.compile(r"\bGRANT\b.*\bTO\b.*\banon\b", re.IGNORECASE)
    n_files = 0
    for path in iter_sql_files():
        n_files += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            if line_pat.search(line):
                snippet = " ".join(line.split())[:240]
                anon_hits.append(
                    {
                        "file": str(path.relative_to(ROOT)),
                        "line": i,
                        "snippet": snippet,
                    }
                )
    return {"grant_to_anon_hits": anon_hits, "sql_files_scanned": n_files}


def scan_code() -> dict:
    hits: list[dict] = []
    for base in CODE_DIRS:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".dart", ".html", ".js", ".ts", ".tsx", ".json"}:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if SERVICE_ROLE_IN_LIB.search(line) or SUPABASE_KEY.search(line):
                    hits.append(
                        {
                            "file": str(path.relative_to(ROOT)),
                            "line": i,
                            "preview": line.strip()[:200],
                        }
                    )
    return {"suspicious_code_hits": hits}


def write_outputs(sql: dict, code: dict, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repository_root": str(ROOT),
        "sql": sql,
        "code": code,
    }
    (out_dir / "inventory.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # CSV summary
    csv_path = out_dir / "inventory_summary.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["category", "file", "line", "detail"])
        for h in sql["grant_to_anon_hits"]:
            w.writerow(["sql_grant_anon", h["file"], h["line"], h["snippet"]])
        for h in code["suspicious_code_hits"]:
            w.writerow(["code_review", h["file"], h["line"], h["preview"]])

    # Markdown report
    md = []
    md.append("# Security inventory (static)\n")
    md.append(f"Generated (UTC): `{payload['generated_at_utc']}`\n")
    md.append("\n## SQL: GRANT … TO anon\n")
    md.append(f"Total hits: **{len(sql['grant_to_anon_hits'])}** (review each — many are intentional public reads).\n")
    for h in sql["grant_to_anon_hits"][:200]:
        md.append(f"- `{h['file']}`:{h['line']} — `{h['snippet']}`\n")
    if len(sql["grant_to_anon_hits"]) > 200:
        md.append("\n> Truncated at 200 rows; see `inventory.json` for full list.\n")

    md.append("\n## Code: heuristic secret / service_role hits\n")
    md.append(f"Total hits: **{len(code['suspicious_code_hits'])}** (manual false positives likely — e.g. comments).\n")
    for h in code["suspicious_code_hits"][:200]:
        md.append(f"- `{h['file']}`:{h['line']} — `{h['preview']}`\n")
    if len(code["suspicious_code_hits"]) > 200:
        md.append("\n> Truncated at 200 rows.\n")

    md.append("\n## Next steps\n")
    md.append("- Merge with live catalog: `supabase/sql/audit_rls_regc_privileges_and_policies.sql`\n")
    md.append("- Run staging validators: `supabase/sql/staging_validation/`\n")

    (out_dir / "inventory_report.md").write_text("".join(md), encoding="utf-8")


def main() -> int:
    out_dir = Path(__file__).resolve().parent / "out"
    sql = scan_sql()
    code = scan_code()
    write_outputs(sql, code, out_dir)
    print(f"Wrote: {out_dir / 'inventory_report.md'}")
    print(f"Wrote: {out_dir / 'inventory.json'}")
    print(f"Wrote: {out_dir / 'inventory_summary.csv'}")
    print(
        f"Summary: sql_anon_grants={len(sql['grant_to_anon_hits'])} "
        f"code_hits={len(code['suspicious_code_hits'])}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
