-- إصلاح digest على Supabase المستضاف (pgcrypto في schema extensions).
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public._user_sessions_ip_hash(p_ip text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT encode(
    extensions.digest(
      convert_to(
        coalesce(nullif(trim(p_ip), ''), '-') || '|aqar_user_ip_pepper_v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;
