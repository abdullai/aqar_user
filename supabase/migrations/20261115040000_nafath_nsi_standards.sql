-- Nafath NSI callback persistence and one-time Supabase session issuance.
BEGIN;

ALTER TABLE public.nafath_logins
  ADD COLUMN IF NOT EXISTS locale text NOT NULL DEFAULT 'ar',
  ADD COLUMN IF NOT EXISTS jwt_kid text,
  ADD COLUMN IF NOT EXISTS error_code text,
  ADD COLUMN IF NOT EXISTS session_issued_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_nafath_logins_final_status_created
  ON public.nafath_logins (status, created_at DESC)
  WHERE status IN ('COMPLETED', 'REJECTED', 'EXPIRED');

CREATE OR REPLACE FUNCTION public.complete_nafath_callback(
  p_request_id uuid,
  p_trans_id text,
  p_status text,
  p_jwt_kid text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_national_id text;
  v_profile_user_count integer;
  v_profile_user_id uuid;
  v_current_status text;
BEGIN
  IF p_status NOT IN ('COMPLETED', 'REJECTED') THEN
    RETURN false;
  END IF;

  UPDATE public.nafath_logins
  SET
    status = p_status,
    jwt_kid = p_jwt_kid,
    updated_at = now(),
    completed_at = CASE WHEN p_status = 'COMPLETED' THEN now() ELSE completed_at END,
    rejected_at = CASE WHEN p_status = 'REJECTED' THEN now() ELSE rejected_at END
  WHERE id = p_request_id
    AND trans_id = p_trans_id
    AND status = 'WAITING'
  RETURNING national_id INTO v_national_id;

  IF NOT FOUND THEN
    SELECT status
    INTO v_current_status
    FROM public.nafath_logins
    WHERE id = p_request_id AND trans_id = p_trans_id;

    RETURN v_current_status = p_status;
  END IF;

  IF p_status = 'COMPLETED' THEN
    SELECT count(DISTINCT user_id)::integer
    INTO v_profile_user_count
    FROM public.users_profiles
    WHERE national_id = v_national_id
      AND user_id IS NOT NULL;

    IF v_profile_user_count = 1 THEN
      SELECT user_id
      INTO v_profile_user_id
      FROM public.users_profiles
      WHERE national_id = v_national_id
        AND user_id IS NOT NULL
      LIMIT 1;

      UPDATE public.users_profiles
      SET
        nafath_verified_at = now(),
        auth_method = 'nafath',
        updated_at = now()
      WHERE user_id = v_profile_user_id;

      UPDATE public.nafath_logins
      SET auth_user_id = v_profile_user_id
      WHERE id = p_request_id;
    END IF;
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_nafath_session(p_request_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  UPDATE public.nafath_logins
  SET session_issued_at = now(), updated_at = now()
  WHERE id = p_request_id
    AND status = 'COMPLETED'
    AND auth_user_id IS NOT NULL
    AND session_issued_at IS NULL
  RETURNING auth_user_id INTO v_user_id;

  RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_nafath_callback(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_nafath_session(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_nafath_callback(uuid, text, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_nafath_session(uuid)
  TO service_role;

COMMIT;
