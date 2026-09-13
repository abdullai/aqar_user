-- دليل مستخدمين بفلاتر، نشاط دخول/خروج، حملات إشعار داخل التطبيق + طابور FCM.
-- نفّذ هذا الملف في محرّر SQL بعد نجاح 20260829230000.

BEGIN;

DROP FUNCTION IF EXISTS public.platform_staff_directory(text, int);
DROP FUNCTION IF EXISTS public.platform_staff_directory(text, int, text);

CREATE OR REPLACE FUNCTION public.platform_staff_directory(
  p_q text DEFAULT '',
  p_limit int DEFAULT 40,
  p_filter text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q text := trim(coalesce(p_q, ''));
  v_lim int := GREATEST(1, LEAST(coalesce(p_limit, 40), 80));
  v_f text := lower(trim(coalesce(p_filter, 'all')));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(x)
      FROM (
        SELECT jsonb_build_object(
          'user_id', up.user_id,
          'username', up.username,
          'account_type', coalesce(up.account_type, ''),
          'name', coalesce(
            nullif(trim(up.full_name_ar), ''),
            nullif(trim(up.full_name), ''),
            ''
          ),
          'verification', coalesce(up.verification_status::text, ''),
          'last_login', coalesce(up.last_verified_login_at, up.last_login_at),
          'last_logout', (
            SELECT max(ls.logout_at) FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id AND ls.logout_at IS NOT NULL
          ),
          'is_staff', EXISTS (
            SELECT 1 FROM public.platform_staff s
            WHERE s.user_id = up.user_id AND coalesce(s.is_active, true)
          ),
          'banned', EXISTS (
            SELECT 1 FROM public.banned_accounts b
            WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
          ),
          'locked', EXISTS (
            SELECT 1 FROM public.banned_accounts b
            WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
              AND coalesce(b.blocks_app, true)
          ),
          'logins', (
            SELECT count(*)::int FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id
          ),
          'logouts', (
            SELECT count(*)::int FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id AND ls.logout_at IS NOT NULL
          ),
          'active_sessions', (
            SELECT count(*)::int FROM public.user_login_sessions ls
            WHERE ls.user_id = up.user_id AND coalesce(ls.is_active, false)
          ),
          'sales', (
            SELECT count(*)::int FROM public.billing_transactions bt
            WHERE bt.user_id = up.user_id AND bt.status = 'success'
          )
        ) AS x
        FROM public.users_profiles up
        WHERE (v_q = ''
           OR up.username ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
           OR up.user_id::text ILIKE '%' || v_q || '%')
          AND (
            v_f = 'all'
            OR (v_f = 'staff' AND EXISTS (
              SELECT 1 FROM public.platform_staff s
              WHERE s.user_id = up.user_id AND coalesce(s.is_active, true)
            ))
            OR (v_f = 'banned' AND EXISTS (
              SELECT 1 FROM public.banned_accounts b
              WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
            ))
            OR (v_f = 'locked' AND EXISTS (
              SELECT 1 FROM public.banned_accounts b
              WHERE b.user_id = up.user_id AND b.lifted_at IS NULL
                AND coalesce(b.blocks_app, true)
            ))
            OR (v_f = 'pending' AND (
              coalesce(up.verification_status::text, '') ILIKE '%pending%'
              OR coalesce(up.verification_status::text, '') ILIKE '%unverified%'
            ))
            OR (v_f = 'active' AND coalesce(up.last_verified_login_at, up.last_login_at) > now() - interval '7 days')
            OR (v_f = 'inactive' AND coalesce(up.last_verified_login_at, up.last_login_at) <= now() - interval '7 days'
              AND coalesce(up.last_verified_login_at, up.last_login_at) >= now() - interval '30 days')
            OR (v_f = 'idle' AND (
              coalesce(up.last_verified_login_at, up.last_login_at) IS NULL
              OR coalesce(up.last_verified_login_at, up.last_login_at) < now() - interval '30 days'
            ))
            OR (v_f IN ('office', 'company', 'institution', 'marketer', 'agency')
                AND lower(coalesce(up.account_type, '')) = v_f)
            OR (v_f = 'owner' AND lower(coalesce(up.account_type, '')) IN (
              'owner_individual', 'individual_seller'
            ))
          )
        ORDER BY coalesce(up.last_verified_login_at, up.last_login_at) DESC NULLS LAST
        LIMIT v_lim
      ) z
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_user_intel()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'most_logins', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', t.user_id,
        'cnt', t.cnt,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
        'account_type', coalesce(up.account_type, '')
      ) ORDER BY t.cnt DESC)
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
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', t.user_id,
        'cnt', t.cnt,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
        'account_type', coalesce(up.account_type, '')
      ) ORDER BY t.cnt DESC)
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

CREATE TABLE IF NOT EXISTS public.ops_push_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  title_ar text NOT NULL DEFAULT '',
  title_en text NOT NULL DEFAULT '',
  body_ar text NOT NULL DEFAULT '',
  body_en text NOT NULL DEFAULT '',
  media_url text,
  deep_route text NOT NULL DEFAULT 'user_dashboard',
  account_type text NOT NULL DEFAULT '',
  target_q text NOT NULL DEFAULT '',
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  status text NOT NULL DEFAULT 'scheduled',
  sent_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ops_push_campaigns
  ADD COLUMN IF NOT EXISTS target_q text NOT NULL DEFAULT '';

ALTER TABLE public.ops_push_campaigns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ops_push_campaigns_staff_read ON public.ops_push_campaigns;
CREATE POLICY ops_push_campaigns_staff_read ON public.ops_push_campaigns
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

DROP FUNCTION IF EXISTS public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text);

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_campaign(
  p_title_ar text,
  p_title_en text,
  p_body_ar text,
  p_body_en text,
  p_media_url text DEFAULT NULL,
  p_deep_route text DEFAULT 'user_dashboard',
  p_account_type text DEFAULT '',
  p_starts_at timestamptz DEFAULT now(),
  p_ends_at timestamptz DEFAULT NULL,
  p_target_q text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_ads FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_team_comms FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_campaign');
  END IF;
  INSERT INTO public.ops_push_campaigns (
    created_by, title_ar, title_en, body_ar, body_en, media_url,
    deep_route, account_type, target_q, starts_at, ends_at, status
  ) VALUES (
    v_uid,
    coalesce(p_title_ar, ''),
    coalesce(p_title_en, ''),
    coalesce(p_body_ar, ''),
    coalesce(p_body_en, ''),
    nullif(trim(coalesce(p_media_url, '')), ''),
    coalesce(nullif(trim(p_deep_route), ''), 'user_dashboard'),
    coalesce(p_account_type, ''),
    trim(coalesce(p_target_q, '')),
    coalesce(p_starts_at, now()),
    p_ends_at,
    'scheduled'
  ) RETURNING id INTO v_id;
  PERFORM public._staff_audit('campaign', 'ops_push_campaigns', v_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_dispatch_campaign(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  c public.ops_push_campaigns%ROWTYPE;
  r record;
  v_n int := 0;
  v_q text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT * INTO c FROM public.ops_push_campaigns WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF now() < c.starts_at THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_started', 'status', 'scheduled');
  END IF;
  IF c.ends_at IS NOT NULL AND now() > c.ends_at THEN
    UPDATE public.ops_push_campaigns SET status = 'expired' WHERE id = p_id;
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  v_q := trim(coalesce(c.target_q, ''));

  FOR r IN
    SELECT up.user_id
    FROM public.users_profiles up
    WHERE (c.account_type = '' OR lower(coalesce(up.account_type, '')) = lower(c.account_type))
      AND (
        v_q = ''
        OR up.username ILIKE '%' || v_q || '%'
        OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
        OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
      )
    LIMIT 400
  LOOP
    BEGIN
      PERFORM public.workflow_create_notification(
        r.user_id,
        'ops_push',
        coalesce(nullif(trim(c.title_ar), ''), 'إشعار المنصة'),
        coalesce(nullif(trim(c.body_ar), ''), c.body_en),
        'ops',
        p_id,
        jsonb_build_object(
          'title_ar', c.title_ar,
          'title_en', c.title_en,
          'body_ar', c.body_ar,
          'body_en', c.body_en,
          'media_url', c.media_url,
          'deep_route', c.deep_route,
          'campaign_id', p_id
        )
      );
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  UPDATE public.ops_push_campaigns
  SET status = 'sent', sent_count = v_n
  WHERE id = p_id;
  PERFORM public._staff_audit('dispatch_campaign', 'ops_push_campaigns', p_id::text, jsonb_build_object('sent', v_n));
  RETURN jsonb_build_object('ok', true, 'sent', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_run_due_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_n int := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  UPDATE public.ops_push_campaigns
  SET status = 'expired'
  WHERE status = 'scheduled' AND ends_at IS NOT NULL AND ends_at <= now();
  FOR r IN
    SELECT id FROM public.ops_push_campaigns
    WHERE status = 'scheduled'
      AND starts_at <= now()
      AND (ends_at IS NULL OR ends_at > now())
    LIMIT 8
  LOOP
    PERFORM public.platform_staff_dispatch_campaign(r.id);
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'ran', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id,
        'title_ar', c.title_ar,
        'title_en', c.title_en,
        'body_ar', c.body_ar,
        'body_en', c.body_en,
        'account_type', c.account_type,
        'target_q', c.target_q,
        'deep_route', c.deep_route,
        'starts_at', c.starts_at,
        'ends_at', c.ends_at,
        'status', c.status,
        'sent_count', c.sent_count,
        'media_url', c.media_url
      ) ORDER BY c.created_at DESC)
      FROM public.ops_push_campaigns c
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_directory(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_directory(text, int, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_user_intel() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_user_intel() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_campaign(text, text, text, text, text, text, text, timestamptz, timestamptz, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_dispatch_campaign(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_dispatch_campaign(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_run_due_campaigns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_run_due_campaigns() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_list_campaigns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_campaigns() TO authenticated;

COMMIT;
