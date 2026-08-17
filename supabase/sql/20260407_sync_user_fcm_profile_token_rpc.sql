-- =============================================================================
-- RPC: تحديث fcm_token في users_profiles للمستخدم الحالي فقط (بدون فتح UPDATE عام)
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_user_fcm_profile_token(p_fcm_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t text := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF length(v_t) < 32 THEN
    RETURN;
  END IF;

  UPDATE public.users_profiles
  SET
    fcm_token = v_t,
    fcm_token_updated_at = now()
  WHERE user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.sync_user_fcm_profile_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_user_fcm_profile_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_user_fcm_profile_token(text) TO service_role;

COMMENT ON FUNCTION public.sync_user_fcm_profile_token(text) IS
  'يحدّث عمودي fcm_token و fcm_token_updated_at لصف المستخدم الحالي فقط.';

COMMIT;
