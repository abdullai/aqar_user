-- نبض الجمهور: أعداد، قوائم مراقبة، إشعار، استكمال ملف بعد التحقق من التذكرة.
-- نفّذ بعد نجاح 20260829290000. لا يغيّر الربط الحكومي.

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fal_license_expires_at timestamptz;

CREATE OR REPLACE FUNCTION public.platform_staff_user_intel()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_guests int := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  BEGIN
    SELECT count(*)::int INTO v_guests
    FROM auth.users au
    WHERE coalesce(au.is_anonymous, false)
      AND coalesce(au.last_sign_in_at, au.created_at) > now() - interval '7 days';
  EXCEPTION WHEN OTHERS THEN
    v_guests := 0;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'users_total', (SELECT count(*)::int FROM public.users_profiles),
    'online_now', (
      SELECT count(*)::int FROM public.users_profiles
      WHERE chat_last_seen_at > now() - interval '2 minutes'
    ),
    'idle_30d', (
      SELECT count(*)::int FROM public.users_profiles
      WHERE coalesce(last_verified_login_at, last_login_at) IS NULL
         OR coalesce(last_verified_login_at, last_login_at) < now() - interval '30 days'
    ),
    'incomplete', (
      SELECT count(*)::int FROM public.users_profiles up
      WHERE coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), nullif(trim(up.first_name_ar), ''), '') = ''
         OR length(regexp_replace(coalesce(up.national_id, up.username, ''), '\D', '', 'g')) <> 10
    ),
    'fal_expired', (
      SELECT count(*)::int FROM public.users_profiles
      WHERE fal_license_expires_at IS NOT NULL AND fal_license_expires_at <= now()
    ),
    'fal_expiring', (
      SELECT count(*)::int FROM public.users_profiles
      WHERE fal_license_expires_at > now()
        AND fal_license_expires_at <= now() + interval '7 days'
    ),
    'subs_expired', (
      SELECT count(*)::int FROM public.user_subscriptions
      WHERE status = 'expired'
         OR (status = 'active' AND coalesce(ends_at, end_date::timestamptz) <= now())
    ),
    'subs_expiring', (
      SELECT count(*)::int FROM public.user_subscriptions
      WHERE status = 'active'
        AND coalesce(ends_at, end_date::timestamptz) > now()
        AND coalesce(ends_at, end_date::timestamptz) <= now() + interval '7 days'
    ),
    'guests_7d', v_guests,
    'by_type', coalesce((
      SELECT jsonb_object_agg(k, c)
      FROM (
        SELECT lower(coalesce(nullif(trim(account_type), ''), 'user')) AS k,
               count(*)::int AS c
        FROM public.users_profiles
        GROUP BY 1
      ) t
    ), '{}'::jsonb),
    'most_logins', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', t.user_id))
        || jsonb_build_object('cnt', t.cnt)
        ORDER BY t.cnt DESC
      )
      FROM (
        SELECT user_id, count(*)::int AS cnt
        FROM public.user_login_sessions
        GROUP BY user_id
        ORDER BY count(*) DESC
        LIMIT 15
      ) t
      LEFT JOIN public.users_profiles up ON up.user_id = t.user_id
    ), '[]'::jsonb),
    'most_sales', coalesce((
      SELECT jsonb_agg(
        coalesce(public._ops_person_json(up), jsonb_build_object('user_id', t.user_id))
        || jsonb_build_object('cnt', t.cnt)
        ORDER BY t.cnt DESC
      )
      FROM (
        SELECT user_id, count(*)::int AS cnt
        FROM public.billing_transactions
        WHERE status = 'success'
        GROUP BY user_id
        ORDER BY count(*) DESC
        LIMIT 15
      ) t
      LEFT JOIN public.users_profiles up ON up.user_id = t.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_watch_list(
  p_kind text,
  p_limit int DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_k text := lower(trim(coalesce(p_kind, '')));
  v_lim int := GREATEST(1, LEAST(coalesce(p_limit, 40), 80));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'kind', v_k,
    'rows', coalesce((
      SELECT jsonb_agg(x)
      FROM (
        SELECT public._ops_person_json(up) || jsonb_build_object(
          'fal_license_expires_at', up.fal_license_expires_at,
          'last_login', coalesce(up.last_verified_login_at, up.last_login_at),
          'sub_ends', (
            SELECT max(coalesce(s.ends_at, s.end_date::timestamptz))
            FROM public.user_subscriptions s
            WHERE s.user_id = up.user_id
          )
        ) AS x
        FROM public.users_profiles up
        WHERE
          (v_k = 'idle' AND (
            coalesce(up.last_verified_login_at, up.last_login_at) IS NULL
            OR coalesce(up.last_verified_login_at, up.last_login_at) < now() - interval '30 days'
          ))
          OR (v_k = 'incomplete' AND (
            coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), nullif(trim(up.first_name_ar), ''), '') = ''
            OR length(regexp_replace(coalesce(up.national_id, up.username, ''), '\D', '', 'g')) <> 10
          ))
          OR (v_k = 'fal_expired' AND up.fal_license_expires_at IS NOT NULL AND up.fal_license_expires_at <= now())
          OR (v_k = 'fal_expiring' AND up.fal_license_expires_at > now()
              AND up.fal_license_expires_at <= now() + interval '7 days')
          OR (v_k IN ('sub_expired', 'sub_expiring') AND EXISTS (
            SELECT 1 FROM public.user_subscriptions s
            WHERE s.user_id = up.user_id
              AND (
                (v_k = 'sub_expired' AND (
                  s.status = 'expired'
                  OR (s.status = 'active' AND coalesce(s.ends_at, s.end_date::timestamptz) <= now())
                ))
                OR (v_k = 'sub_expiring' AND s.status = 'active'
                    AND coalesce(s.ends_at, s.end_date::timestamptz) > now()
                    AND coalesce(s.ends_at, s.end_date::timestamptz) <= now() + interval '7 days')
              )
          ))
        ORDER BY coalesce(up.last_verified_login_at, up.last_login_at) DESC NULLS LAST
        LIMIT v_lim
      ) z
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_notify_watch(
  p_kind text,
  p_title_ar text,
  p_title_en text,
  p_body_ar text,
  p_body_en text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_n int := 0;
  r record;
  v_list jsonb;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_support FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_ads FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_team_comms FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_staff), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_notify');
  END IF;
  IF length(trim(coalesce(p_title_ar, ''))) < 2 OR length(trim(coalesce(p_body_ar, ''))) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'text_required');
  END IF;

  v_list := public.platform_staff_watch_list(p_kind, 80);
  FOR r IN
    SELECT (e->>'user_id')::uuid AS uid
    FROM jsonb_array_elements(coalesce(v_list->'rows', '[]'::jsonb)) e
    WHERE nullif(e->>'user_id', '') IS NOT NULL
  LOOP
    BEGIN
      PERFORM public.workflow_create_notification(
        r.uid,
        'ops_notice',
        trim(p_title_ar),
        trim(p_body_ar),
        'ops_watch',
        NULL,
        jsonb_build_object(
          'title_ar', trim(p_title_ar),
          'title_en', trim(coalesce(p_title_en, p_title_ar)),
          'body_ar', trim(p_body_ar),
          'body_en', trim(coalesce(p_body_en, p_body_ar)),
          'kind', p_kind
        )
      );
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  PERFORM public._staff_audit(
    'notify_watch', 'users_profiles', p_kind,
    jsonb_build_object('sent', v_n, 'kind', p_kind)
  );
  RETURN jsonb_build_object('ok', true, 'sent', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_patch_profile(
  p_user_id uuid,
  p_full_name_ar text DEFAULT NULL,
  p_full_name_en text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_national_id text DEFAULT NULL,
  p_office_name text DEFAULT NULL,
  p_license_no text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_nid text;
  v_phone text;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_support FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_moderate FROM public.platform_staff WHERE user_id = v_staff), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_patch');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;

  v_nid := nullif(regexp_replace(coalesce(p_national_id, ''), '\D', '', 'g'), '');
  IF v_nid IS NOT NULL AND length(v_nid) <> 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'national_id_10');
  END IF;
  v_phone := nullif(trim(coalesce(p_phone, '')), '');

  UPDATE public.users_profiles
  SET
    full_name_ar = coalesce(nullif(trim(p_full_name_ar), ''), full_name_ar),
    full_name_en = coalesce(nullif(trim(p_full_name_en), ''), full_name_en),
    phone = coalesce(v_phone, phone),
    national_id = coalesce(v_nid, national_id),
    username = CASE
      WHEN v_nid IS NOT NULL AND (username IS NULL OR username ~ '^[0-9]{10}$')
      THEN v_nid ELSE username
    END,
    office_name = coalesce(nullif(trim(p_office_name), ''), office_name),
    license_no = coalesce(nullif(trim(p_license_no), ''), license_no)
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  PERFORM public._staff_audit(
    'patch_profile', 'users_profiles', p_user_id::text,
    jsonb_build_object(
      'name_ar', p_full_name_ar,
      'national_id', v_nid,
      'phone', v_phone
    )
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_watch_list(text, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_notify_watch(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_patch_profile(uuid, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_user_intel() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_watch_list(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_notify_watch(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_patch_profile(uuid, text, text, text, text, text, text) TO authenticated;

COMMIT;
