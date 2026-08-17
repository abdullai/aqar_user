BEGIN;

CREATE TABLE IF NOT EXISTS public.nafath_logins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trans_id text NOT NULL UNIQUE,
  random text NOT NULL,
  national_id text NOT NULL,
  flow text NOT NULL DEFAULT 'login',
  status text NOT NULL DEFAULT 'PENDING',
  auth_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  callback_payload jsonb,
  auth_link text,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  rejected_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_nafath_logins_national_created
  ON public.nafath_logins (national_id, created_at DESC);

ALTER TABLE public.nafath_logins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nafath_logins_no_client_access
  ON public.nafath_logins;
CREATE POLICY nafath_logins_no_client_access
  ON public.nafath_logins
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

COMMIT;
