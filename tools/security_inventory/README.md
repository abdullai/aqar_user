# Security inventory scanner (repository static analysis)

**Path:** `tools/security_inventory/scan.py`  
**Language:** Python 3.9+ (stdlib only — no `pip install`).

## What it does

- Scans `supabase/migrations`, `supabase/sql` for `GRANT … TO anon` / `TO authenticated` patterns.  
- Scans `lib/`, `web/` for **suspicious** secret-like strings (heuristic).  
- Writes **`out/`** (gitignored recommended — see below): `inventory_report.md`, `inventory.json`, `inventory_summary.csv`.

## Run

```bash
cd tools/security_inventory
python scan.py
```

On Windows PowerShell:

```powershell
cd d:\aqar_user\tools\security_inventory
python scan.py
```

## Outputs

| File | Format |
|------|--------|
| `out/inventory_report.md` | Human-readable |
| `out/inventory.json` | Machine-readable |
| `out/inventory_summary.csv` | Spreadsheet-friendly |

> **Note:** Live Postgres catalog checks (RLS on/off per table) belong in Supabase SQL Editor — use `supabase/sql/audit_rls_regc_privileges_and_policies.sql` and `staging_validation/` suite.

## Optional: ignore `out/` in git

Add `tools/security_inventory/out/` to `.gitignore` if you do not want generated artifacts committed.
