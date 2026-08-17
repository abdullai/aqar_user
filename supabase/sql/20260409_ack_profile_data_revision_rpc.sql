BEGIN;

CREATE OR REPLACE FUNCTION public.ack_profile_data_revision(p_target integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_target IS NULL OR p_target < 1 THEN
    RAISE EXCEPTION 'invalid_target';
  END IF;

  UPDATE public.users_profiles
  SET profile_data_revision = p_target
  WHERE user_id = auth.uid()
    AND COALESCE(profile_data_revision, 0) < p_target;
END;
$$;

REVOKE ALL ON FUNCTION public.ack_profile_data_revision(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ack_profile_data_revision(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ack_profile_data_revision(integer) TO service_role;

COMMIT;
