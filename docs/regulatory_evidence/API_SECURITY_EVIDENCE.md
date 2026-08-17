# API_SECURITY_EVIDENCE

## Architectural summary

The Flutter client talks to **Supabase PostgREST** over HTTPS using the **anon** public key plus a **user JWT** after login. Sensitive writes on compliance tables go through **parameterized RPCs** (`SECURITY DEFINER`) that bind `auth.uid()` server-side.

## RPC surface (compliance — excerpt)

```sql
CREATE OR REPLACE FUNCTION public.compliance_append_audit(
  p_event_type text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  -- ...
  INSERT INTO public.regc_audit_logs (user_id, event_type, metadata)
  VALUES (v_uid, trim(p_event_type), coalesce(p_metadata, '{}'::jsonb));
END;
$$;
```

## Role separation

| Key | Use |
|-----|-----|
| `anon` | Unauthenticated reads allowed by policy only (e.g. active legal text). |
| `authenticated` | User-scoped DML per RLS + EXECUTE on approved RPCs. |
| `service_role` | **Never** in mobile/web builds; CI / admin backend only. |

## Example “log line” (operator narrative)

> `POST /rest/v1/rpc/compliance_append_audit` with `Authorization: Bearer <user_jwt>` returns `204` and inserts one row with `user_id` equal to JWT `sub` — verified on staging.

## Abuse scenarios (document results)

- Call RPC **without** JWT → expect `401` / `not_authenticated`.  
- Call RPC with **anon key only** → expect failure (no `auth.uid()`).

**Validator:** `supabase/sql/staging_validation/validate_jwt_claims.sql` (function presence + grant checks).
