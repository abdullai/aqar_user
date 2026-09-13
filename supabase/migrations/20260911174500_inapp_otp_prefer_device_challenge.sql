-- Device-management OTP must verify the inapp_otp challenge, not a leftover login one.
BEGIN;

CREATE OR REPLACE FUNCTION public.verify_inapp_otp(
  p_username text,
  p_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  digits text := regexp_replace(trim(coalesce(p_code, '')), '\D', '', 'g');
  cid uuid;
  res jsonb;
BEGIN
  IF uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT c.id INTO cid
  FROM public.auth_login_challenges c
  WHERE c.user_id = uid
    AND c.status = 'pending'
    AND c.otp_expires_at > timezone('utc', now())
  ORDER BY CASE WHEN c.purpose = 'inapp_otp' THEN 0 ELSE 1 END,
           c.created_at DESC
  LIMIT 1;

  IF cid IS NULL THEN
    RETURN false;
  END IF;

  res := public.verify_login_otp(cid, digits);
  RETURN coalesce((res->>'ok')::boolean, false);
END;
$$;

REVOKE ALL ON FUNCTION public.verify_inapp_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_inapp_otp(text, text) TO authenticated;

COMMIT;
