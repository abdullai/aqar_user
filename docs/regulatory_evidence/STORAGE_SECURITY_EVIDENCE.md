# STORAGE_SECURITY_EVIDENCE

## Architectural summary

Binary assets (listing images, documents) use **Supabase Storage** with **bucket policies** separate from Postgres RLS. Evidence should include a **screenshot export** from the Supabase dashboard for each bucket (public vs private, allowed MIME, max size).

## Recommended controls (operator checklist)

- Private buckets for ID / contract PDFs; **signed URLs** with short TTL.  
- Deny anonymous **write** on all buckets.  
- Path prefix convention: `{user_id}/...` enforced in policy where possible.

## SQL inventory (staging)

```sql
SELECT schemaname, tablename, policyname, roles, cmd, qual::text
FROM pg_policies
WHERE schemaname = 'storage'
ORDER BY tablename, policyname;
```

**Validator:** `supabase/sql/staging_validation/validate_storage_policies.sql`

## MIME / malware (placeholder)

Document integration point for server-side scanning (ClamAV / cloud AV) in deployment runbook — not enforced in-repo.
