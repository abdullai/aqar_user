BEGIN;

CREATE TABLE IF NOT EXISTS public.wathq_access_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  resource_type text NOT NULL CHECK (resource_type IN (
    'commercial_registration', 'national_address', 'real_estate_deed'
  )),
  identifier text NOT NULL,
  owner_id text NOT NULL DEFAULT '',
  owner_id_type text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (resource_type = 'real_estate_deed' AND owner_id <> '' AND owner_id_type <> '')
    OR (resource_type <> 'real_estate_deed' AND owner_id = '' AND owner_id_type = '')
  ),
  UNIQUE (user_id, resource_type, identifier, owner_id, owner_id_type)
);

ALTER TABLE public.wathq_access_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wathq_access_grants FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.wathq_access_grants TO service_role;

COMMIT;
