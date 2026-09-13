-- Login Challenge + hashed 6-digit OTP + session gate.
-- Server is the source of truth. Clients must not skip OTP from local flags.
-- Development: otp_provider = internal → peek_dev_login_otp may return plaintext.
-- Production: set otp_provider = external_sms | external_email and leave otp_dev_plain NULL.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.auth_runtime_config (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

INSERT INTO public.auth_runtime_config (key, value) VALUES
  ('otp_provider', 'internal'),
  ('otp_ttl_seconds', '90'),
  ('otp_max_attempts', '5'),
  ('otp_rate_max_per_10min', '8'),
  ('nafath_skip_otp_native', 'true'),
  ('nafath_skip_otp_web', 'false')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.auth_runtime_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_runtime_config_no_client ON public.auth_runtime_config;
CREATE POLICY auth_runtime_config_no_client ON public.auth_runtime_config
  FOR ALL TO authenticated, anon
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON TABLE public.auth_runtime_config FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.auth_login_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  username text,
  platform text NOT NULL DEFAULT 'unknown',
  device_fingerprint text,
  purpose text NOT NULL DEFAULT 'login',
  login_method text NOT NULL DEFAULT 'password',
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'verified', 'expired', 'locked', 'consumed', 'cancelled')),
  otp_hash text,
  otp_dev_plain text,
  otp_expires_at timestamptz,
  attempt_count int NOT NULL DEFAULT 0,
  max_attempts int NOT NULL DEFAULT 5,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  verified_at timestamptz,
  consumed_at timestamptz,
  ip text,
  user_agent text
);

CREATE INDEX IF NOT EXISTS auth_login_challenges_user_status_idx
  ON public.auth_login_challenges (user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS auth_login_challenges_user_created_idx
  ON public.auth_login_challenges (user_id, created_at DESC);

ALTER TABLE public.auth_login_challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_login_challenges_no_client ON public.auth_login_challenges;
CREATE POLICY auth_login_challenges_no_client ON public.auth_login_challenges
  FOR ALL TO authenticated, anon
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON TABLE public.auth_login_challenges FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.auth_session_gates (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  session_tag text NOT NULL,
  platform text,
  challenge_id uuid REFERENCES public.auth_login_challenges (id) ON DELETE SET NULL,
  completed_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (user_id, session_tag)
);

ALTER TABLE public.auth_session_gates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_session_gates_no_client ON public.auth_session_gates;
CREATE POLICY auth_session_gates_no_client ON public.auth_session_gates
  FOR ALL TO authenticated, anon
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON TABLE public.auth_session_gates FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.auth_otp_provider()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(trim(coalesce(
    (SELECT value FROM public.auth_runtime_config WHERE key = 'otp_provider' LIMIT 1),
    'internal'
  )));
$$;

CREATE OR REPLACE FUNCTION public.auth_cfg_int(p_key text, p_default int)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  SELECT value INTO v FROM public.auth_runtime_config WHERE key = p_key LIMIT 1;
  IF v IS NULL OR v !~ '^[0-9]+$' THEN
    RETURN p_default;
  END IF;
  RETURN v::int;
END;
$$;

CREATE OR REPLACE FUNCTION public.auth_cfg_bool(p_key text, p_default boolean)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  SELECT lower(trim(value)) INTO v FROM public.auth_runtime_config WHERE key = p_key LIMIT 1;
  IF v IS NULL THEN
    RETURN p_default;
  END IF;
  RETURN v IN ('1', 'true', 't', 'yes', 'on');
END;
$$;

CREATE OR REPLACE FUNCTION public.auth_session_tag()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  j jsonb := auth.jwt();
BEGIN
  IF j IS NULL OR auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN coalesce(
    nullif(j->>'session_id', ''),
    md5(coalesce(j->>'iat', '') || ':' || coalesce(j->>'sub', auth.uid()::text))
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.auth_platform_is_native_mobile(p_platform text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(coalesce(p_platform, ''))) IN ('android', 'ios');
$$;

CREATE OR REPLACE FUNCTION public.auth_otp_hash(
  p_code text,
  p_challenge_id uuid,
  p_user_id uuid
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT encode(
    digest(
      convert_to(
        regexp_replace(trim(coalesce(p_code, '')), '\D', '', 'g')
        || ':' || p_challenge_id::text
        || ':' || p_user_id::text,
        'utf8'
      ),
      'sha256'::text
    ),
    'hex'
  );
$$;

CREATE OR REPLACE FUNCTION public.auth_generate_otp6()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path = public, extensions
AS $$
DECLARE
  raw bytea;
  n bigint;
  code text;
BEGIN
  LOOP
    raw := gen_random_bytes(4);
    n := get_byte(raw, 0)::bigint * 16777216
      + get_byte(raw, 1)::bigint * 65536
      + get_byte(raw, 2)::bigint * 256
      + get_byte(raw, 3)::bigint;
    code := lpad((n % 1000000)::text, 6, '0');
    IF code <> '000000' THEN
      RETURN code;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._auth_complete_session_gate(
  p_user_id uuid,
  p_platform text,
  p_challenge_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tag text := public.auth_session_tag();
BEGIN
  IF p_user_id IS NULL OR tag IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.auth_session_gates (user_id, session_tag, platform, challenge_id, completed_at)
  VALUES (p_user_id, tag, p_platform, p_challenge_id, timezone('utc', now()))
  ON CONFLICT (user_id, session_tag) DO UPDATE
    SET completed_at = excluded.completed_at,
        platform = excluded.platform,
        challenge_id = coalesce(excluded.challenge_id, public.auth_session_gates.challenge_id);
END;
$$;

CREATE OR REPLACE FUNCTION public._auth_device_trusted(
  p_user_id uuid,
  p_fingerprint text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR length(trim(coalesce(p_fingerprint, ''))) < 8 THEN
    RETURN false;
  END IF;
  IF to_regclass('public.user_devices') IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.user_devices d
    WHERE d.user_id = p_user_id
      AND d.device_fingerprint = trim(p_fingerprint)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.eval_login_trust(
  p_platform text,
  p_device_fingerprint text,
  p_login_method text DEFAULT 'password'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  plat text := lower(trim(coalesce(p_platform, 'unknown')));
  method text := lower(trim(coalesce(p_login_method, 'password')));
  native_mobile boolean;
  trusted boolean;
  skip_nafath boolean;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  native_mobile := public.auth_platform_is_native_mobile(plat);
  trusted := native_mobile AND public._auth_device_trusted(uid, p_device_fingerprint);

  IF method = 'fast_unlock' AND NOT native_mobile THEN
    RETURN jsonb_build_object(
      'ok', false,
      'otp_required', true,
      'trusted', false,
      'fully_authenticated', false,
      'error', 'fast_login_forbidden'
    );
  END IF;

  IF NOT native_mobile THEN
    skip_nafath := public.auth_cfg_bool('nafath_skip_otp_web', false);
    RETURN jsonb_build_object(
      'ok', true,
      'otp_required', true,
      'trusted', false,
      'fully_authenticated', false,
      'native_mobile', false,
      'nafath_can_skip', (method = 'nafath' AND skip_nafath)
    );
  END IF;

  skip_nafath := public.auth_cfg_bool('nafath_skip_otp_native', true);

  IF method = 'nafath' AND skip_nafath THEN
    RETURN jsonb_build_object(
      'ok', true,
      'otp_required', false,
      'trusted', trusted,
      'fully_authenticated', false,
      'native_mobile', true,
      'nafath_can_skip', true
    );
  END IF;

  IF method = 'fast_unlock' AND NOT trusted THEN
    RETURN jsonb_build_object(
      'ok', false,
      'otp_required', true,
      'trusted', false,
      'fully_authenticated', false,
      'error', 'device_not_trusted'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'otp_required', NOT trusted,
    'trusted', trusted,
    'fully_authenticated', false,
    'native_mobile', true,
    'nafath_can_skip', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_auth_gate_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  tag text := public.auth_session_tag();
  done timestamptz;
  pending uuid;
BEGIN
  IF uid IS NULL OR tag IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'complete', false, 'error', 'not_authenticated');
  END IF;

  SELECT g.completed_at INTO done
  FROM public.auth_session_gates g
  WHERE g.user_id = uid AND g.session_tag = tag
  LIMIT 1;

  SELECT c.id INTO pending
  FROM public.auth_login_challenges c
  WHERE c.user_id = uid
    AND c.status = 'pending'
    AND c.purpose IN ('login', 'inapp_otp')
    AND c.otp_expires_at IS NOT NULL
    AND c.otp_expires_at > timezone('utc', now())
  ORDER BY c.created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'complete', done IS NOT NULL,
    'needs_otp', done IS NULL AND pending IS NOT NULL,
    'challenge_id', pending
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._auth_issue_otp_challenge(
  p_username text,
  p_platform text,
  p_device_fingerprint text,
  p_purpose text,
  p_login_method text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prof record;
  cid uuid := gen_random_uuid();
  code text;
  ttl int := public.auth_cfg_int('otp_ttl_seconds', 90);
  max_att int := public.auth_cfg_int('otp_max_attempts', 5);
  rate_max int := public.auth_cfg_int('otp_rate_max_per_10min', 8);
  recent int;
  expires_at timestamptz;
  internal boolean;
  provider text := public.auth_otp_provider();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prof
  FROM public._resolve_inapp_otp_profile(p_username)
  LIMIT 1;

  IF prof.profile_user_id IS NULL OR prof.profile_user_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'username_not_current_user';
  END IF;

  SELECT count(*)::int INTO recent
  FROM public.auth_login_challenges c
  WHERE c.user_id = uid
    AND c.created_at > timezone('utc', now()) - interval '10 minutes';

  IF recent >= rate_max THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  UPDATE public.auth_login_challenges
  SET status = 'cancelled',
      consumed_at = timezone('utc', now())
  WHERE user_id = uid
    AND status = 'pending'
    AND purpose = coalesce(nullif(trim(p_purpose), ''), 'login');

  code := public.auth_generate_otp6();
  expires_at := timezone('utc', now()) + make_interval(secs => ttl);
  internal := provider IN ('internal', 'internal_dev');

  INSERT INTO public.auth_login_challenges (
    id, user_id, username, platform, device_fingerprint, purpose, login_method,
    status, otp_hash, otp_dev_plain, otp_expires_at, attempt_count, max_attempts
  ) VALUES (
    cid, uid, prof.profile_username, lower(trim(coalesce(p_platform, 'unknown'))),
    nullif(trim(coalesce(p_device_fingerprint, '')), ''),
    coalesce(nullif(trim(p_purpose), ''), 'login'),
    coalesce(nullif(trim(p_login_method), ''), 'password'),
    'pending',
    public.auth_otp_hash(code, cid, uid),
    CASE WHEN internal THEN code ELSE NULL END,
    expires_at,
    0,
    max_att
  );

  INSERT INTO public.in_app_notifications (
    username, user_id, type, title, body, data, created_at, is_read
  ) VALUES (
    prof.profile_username,
    uid,
    'otp',
    'رمز التحقق',
    CASE WHEN internal
      THEN 'رمز التحقق داخل التطبيق جاهز للاختبار.'
      ELSE 'تم إرسال رمز التحقق عبر القناة الخارجية.'
    END,
    jsonb_build_object(
      'purpose', coalesce(nullif(trim(p_purpose), ''), 'login'),
      'challengeId', cid::text,
      'hasCode', false,
      'expiresAt', to_char(expires_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    ),
    timezone('utc', now()),
    false
  );

  RETURN jsonb_build_object(
    'ok', true,
    'needs_otp', true,
    'fully_authenticated', false,
    'challenge_id', cid,
    'expiresAt', expires_at,
    'expires_at', expires_at,
    'otp_len', 6,
    'dev_code', CASE WHEN internal THEN code ELSE NULL END,
    'otp_provider', provider
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.start_login_challenge(
  p_username text,
  p_platform text DEFAULT 'unknown',
  p_device_fingerprint text DEFAULT NULL,
  p_login_method text DEFAULT 'password',
  p_purpose text DEFAULT 'login'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  eval jsonb;
  plat text := lower(trim(coalesce(p_platform, 'unknown')));
  method text := lower(trim(coalesce(p_login_method, 'password')));
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  eval := public.eval_login_trust(plat, p_device_fingerprint, method);

  IF coalesce(eval->>'ok', 'true') = 'false' AND eval->>'error' = 'fast_login_forbidden' THEN
    RETURN eval || jsonb_build_object('needs_otp', true, 'fully_authenticated', false);
  END IF;

  IF method = 'fast_unlock' THEN
    IF coalesce((eval->>'trusted')::boolean, false) THEN
      PERFORM public._auth_complete_session_gate(uid, plat, NULL);
      RETURN jsonb_build_object(
        'ok', true,
        'needs_otp', false,
        'fully_authenticated', true,
        'trusted', true
      );
    END IF;
    RETURN jsonb_build_object(
      'ok', false,
      'needs_otp', true,
      'fully_authenticated', false,
      'trusted', false,
      'error', coalesce(eval->>'error', 'device_not_trusted')
    );
  END IF;

  IF method = 'nafath' AND coalesce((eval->>'nafath_can_skip')::boolean, false) THEN
    PERFORM public._auth_complete_session_gate(uid, plat, NULL);
    RETURN jsonb_build_object(
      'ok', true,
      'needs_otp', false,
      'fully_authenticated', true,
      'trusted', coalesce((eval->>'trusted')::boolean, false),
      'nafath_skip', true
    );
  END IF;

  IF coalesce((eval->>'otp_required')::boolean, true) IS NOT TRUE
     AND coalesce((eval->>'trusted')::boolean, false) THEN
    PERFORM public._auth_complete_session_gate(uid, plat, NULL);
    IF to_regclass('public.user_devices') IS NOT NULL
       AND length(trim(coalesce(p_device_fingerprint, ''))) >= 8 THEN
      UPDATE public.user_devices
      SET last_seen = timezone('utc', now())
      WHERE user_id = uid AND device_fingerprint = trim(p_device_fingerprint);
    END IF;
    RETURN jsonb_build_object(
      'ok', true,
      'needs_otp', false,
      'fully_authenticated', true,
      'trusted', true
    );
  END IF;

  RETURN public._auth_issue_otp_challenge(
    p_username, plat, p_device_fingerprint, coalesce(nullif(trim(p_purpose), ''), 'login'), method
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_login_otp(
  p_challenge_id uuid,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  digits text := regexp_replace(trim(coalesce(p_code, '')), '\D', '', 'g');
  rec public.auth_login_challenges%ROWTYPE;
  hashed text;
  updated_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  IF length(digits) <> 6 OR p_challenge_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  SELECT * INTO rec
  FROM public.auth_login_challenges
  WHERE id = p_challenge_id
  FOR UPDATE;

  IF rec.id IS NULL OR rec.user_id IS DISTINCT FROM uid THEN
    RETURN jsonb_build_object('ok', false, 'error', 'challenge_not_found');
  END IF;

  IF rec.status IN ('consumed', 'cancelled') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'consumed');
  END IF;

  IF rec.status = 'locked' THEN
    RETURN jsonb_build_object('ok', false, 'locked', true, 'error', 'locked');
  END IF;

  IF rec.status = 'expired' OR rec.otp_expires_at IS NULL OR rec.otp_expires_at <= timezone('utc', now()) THEN
    UPDATE public.auth_login_challenges
    SET status = 'expired'
    WHERE id = rec.id AND status = 'pending';
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  IF rec.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_state');
  END IF;

  hashed := public.auth_otp_hash(digits, rec.id, rec.user_id);

  UPDATE public.auth_login_challenges
  SET status = 'consumed',
      verified_at = timezone('utc', now()),
      consumed_at = timezone('utc', now())
  WHERE id = rec.id
    AND user_id = uid
    AND status = 'pending'
    AND consumed_at IS NULL
    AND otp_expires_at > timezone('utc', now())
    AND attempt_count < rec.max_attempts
    AND otp_hash = hashed
  RETURNING id INTO updated_id;

  IF updated_id IS NOT NULL THEN
    PERFORM public._auth_complete_session_gate(uid, rec.platform, rec.id);
    RETURN jsonb_build_object(
      'ok', true,
      'fully_authenticated', true,
      'challenge_id', rec.id
    );
  END IF;

  UPDATE public.auth_login_challenges
  SET attempt_count = attempt_count + 1,
      status = CASE
        WHEN attempt_count + 1 >= max_attempts THEN 'locked'
        ELSE status
      END
  WHERE id = rec.id
    AND status = 'pending'
  RETURNING status, attempt_count, max_attempts INTO rec.status, rec.attempt_count, rec.max_attempts;

  RETURN jsonb_build_object(
    'ok', false,
    'locked', rec.status = 'locked',
    'remaining_attempts', greatest(rec.max_attempts - rec.attempt_count, 0),
    'error', CASE WHEN rec.status = 'locked' THEN 'locked' ELSE 'invalid_code' END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.peek_dev_login_otp(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  rec public.auth_login_challenges%ROWTYPE;
  provider text := public.auth_otp_provider();
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  IF provider NOT IN ('internal', 'internal_dev') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_internal');
  END IF;

  SELECT * INTO rec
  FROM public.auth_login_challenges
  WHERE id = p_challenge_id
    AND user_id = uid
  LIMIT 1;

  IF rec.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'challenge_not_found');
  END IF;
  IF rec.status <> 'pending' OR rec.otp_expires_at <= timezone('utc', now()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unavailable');
  END IF;
  IF rec.otp_dev_plain IS NULL OR length(rec.otp_dev_plain) <> 6 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_dev_code');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'code', rec.otp_dev_plain,
    'challenge_id', rec.id,
    'expires_at', rec.otp_expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_trusted_native_unlock(
  p_platform text,
  p_device_fingerprint text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.start_login_challenge(
    '',
    p_platform,
    p_device_fingerprint,
    'fast_unlock',
    'login'
  );
END;
$$;

-- Compatibility wrappers used by device management + existing Dart.
CREATE OR REPLACE FUNCTION public.request_inapp_otp(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  plat text := 'unknown';
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  RETURN public._auth_issue_otp_challenge(
    p_username, plat, NULL, 'inapp_otp', 'password'
  );
END;
$$;

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
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF cid IS NULL THEN
    RETURN false;
  END IF;

  res := public.verify_login_otp(cid, digits);
  RETURN coalesce((res->>'ok')::boolean, false);
END;
$$;

REVOKE ALL ON FUNCTION public.auth_platform_is_native_mobile(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_otp_provider() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_cfg_int(text, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_cfg_bool(text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_session_tag() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_otp_hash(text, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auth_generate_otp6() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._auth_complete_session_gate(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._auth_device_trusted(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._auth_issue_otp_challenge(text, text, text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.eval_login_trust(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_auth_gate_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_login_challenge(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_login_otp(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.peek_dev_login_otp(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_trusted_native_unlock(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_inapp_otp(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_inapp_otp(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.eval_login_trust(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_gate_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_login_challenge(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_login_otp(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.peek_dev_login_otp(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_trusted_native_unlock(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_inapp_otp(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_inapp_otp(text, text) TO authenticated;

COMMIT;
