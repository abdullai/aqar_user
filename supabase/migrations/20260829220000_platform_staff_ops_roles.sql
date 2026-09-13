-- تشغيل المنصة: أدوار متعددة، نشاط، منح من المالك، دليل مستخدمين، إعلانات دخول، رسوم.
-- لا يخلط account_type (السوق) مع تشغيل المنصة.

BEGIN;

ALTER TABLE public.platform_staff
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_owner boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_grant boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS roles jsonb NOT NULL DEFAULT '[]'::jsonb;

UPDATE public.platform_staff
SET is_owner = true,
    can_grant = true,
    can_finance = true,
    can_moderate = true,
    can_support = true
WHERE role IN ('owner', 'admin');

UPDATE public.platform_staff
SET roles = (
  SELECT coalesce(jsonb_agg(x), '[]'::jsonb)
  FROM (
    SELECT v.x
    FROM (VALUES
      ('support'),
      ('compliance'),
      ('finance'),
      ('owner')
    ) AS v(x)
    WHERE (v.x = 'support' AND coalesce(platform_staff.can_support, false))
       OR (v.x = 'compliance' AND coalesce(platform_staff.can_moderate, false))
       OR (v.x = 'finance' AND coalesce(platform_staff.can_finance, false))
       OR (v.x = 'owner' AND coalesce(platform_staff.is_owner, false))
  ) s
)
WHERE roles = '[]'::jsonb OR roles IS NULL;

CREATE OR REPLACE FUNCTION public.is_platform_staff(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_staff s
    WHERE s.user_id = p_uid
      AND coalesce(s.is_active, true)
  );
$$;

CREATE OR REPLACE FUNCTION public._staff_can_grant(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_staff s
    WHERE s.user_id = p_uid
      AND coalesce(s.is_active, true)
      AND (coalesce(s.is_owner, false) OR coalesce(s.can_grant, false))
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_platform_staff_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.platform_staff%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO r FROM public.platform_staff s WHERE s.user_id = v_uid;
  IF NOT FOUND OR NOT coalesce(r.is_active, true) THEN
    RETURN jsonb_build_object('ok', true, 'is_staff', false);
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'is_staff', true,
    'is_owner', coalesce(r.is_owner, false),
    'can_grant', coalesce(r.can_grant, false) OR coalesce(r.is_owner, false),
    'role', r.role,
    'roles', coalesce(r.roles, '[]'::jsonb),
    'can_finance', r.can_finance,
    'can_moderate', r.can_moderate,
    'can_support', r.can_support,
    'is_active', r.is_active
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_directory(
  p_q text DEFAULT '',
  p_limit int DEFAULT 40
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
          'is_staff', EXISTS (
            SELECT 1 FROM public.platform_staff s
            WHERE s.user_id = up.user_id AND coalesce(s.is_active, true)
          )
        ) AS x
        FROM public.users_profiles up
        WHERE v_q = ''
           OR up.username ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
           OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
        ORDER BY up.username
        LIMIT v_lim
      ) z
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_team_list()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public._staff_can_grant(auth.uid()) THEN
    IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', s.user_id,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
        'is_owner', s.is_owner,
        'is_active', s.is_active,
        'can_support', s.can_support,
        'can_moderate', s.can_moderate,
        'can_finance', s.can_finance,
        'can_grant', s.can_grant,
        'roles', s.roles
      ) ORDER BY s.is_owner DESC, up.username)
      FROM public.platform_staff s
      LEFT JOIN public.users_profiles up ON up.user_id = s.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_grant_ops(
  p_user_id uuid,
  p_support boolean DEFAULT true,
  p_moderate boolean DEFAULT false,
  p_finance boolean DEFAULT false,
  p_grant boolean DEFAULT false,
  p_active boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_roles jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public._staff_can_grant(v_actor) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;
  IF coalesce(p_grant, false) AND NOT coalesce(
    (SELECT is_owner FROM public.platform_staff WHERE user_id = v_actor), false
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_only_grant');
  END IF;

  v_roles := '[]'::jsonb;
  IF p_support THEN v_roles := v_roles || '["support"]'::jsonb; END IF;
  IF p_moderate THEN v_roles := v_roles || '["compliance"]'::jsonb; END IF;
  IF p_finance THEN v_roles := v_roles || '["finance"]'::jsonb; END IF;

  INSERT INTO public.platform_staff (
    user_id, role, is_active, is_owner, can_grant,
    can_support, can_moderate, can_finance, roles
  ) VALUES (
    p_user_id,
    CASE WHEN p_finance THEN 'finance' WHEN p_moderate THEN 'compliance' ELSE 'staff' END,
    coalesce(p_active, true),
    false,
    coalesce(p_grant, false),
    coalesce(p_support, true),
    coalesce(p_moderate, false),
    coalesce(p_finance, false),
    v_roles
  )
  ON CONFLICT (user_id) DO UPDATE SET
    is_active = excluded.is_active,
    can_support = excluded.can_support,
    can_moderate = excluded.can_moderate,
    can_finance = excluded.can_finance,
    can_grant = CASE
      WHEN public.platform_staff.is_owner THEN public.platform_staff.can_grant
      ELSE excluded.can_grant
    END,
    roles = excluded.roles;

  PERFORM public._staff_audit(
    'grant_ops', 'platform_staff', p_user_id::text,
    jsonb_build_object(
      'support', p_support,
      'moderate', p_moderate,
      'finance', p_finance,
      'active', p_active
    )
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_revoke_ops(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT public._staff_can_grant(v_actor) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = p_user_id), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_revoke_owner');
  END IF;
  UPDATE public.platform_staff
  SET is_active = false,
      can_support = false,
      can_moderate = false,
      can_finance = false,
      can_grant = false,
      roles = '[]'::jsonb
  WHERE user_id = p_user_id;
  PERFORM public._staff_audit('revoke_ops', 'platform_staff', p_user_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_set_fee(
  p_fee_key text,
  p_amount_sar numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_finance');
  END IF;
  IF p_fee_key IS NULL OR length(trim(p_fee_key)) < 2 OR p_amount_sar IS NULL OR p_amount_sar <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_fee');
  END IF;
  UPDATE public.platform_fee_catalog
  SET amount_sar = p_amount_sar, updated_at = now()
  WHERE fee_key = trim(p_fee_key);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fee');
  END IF;
  PERFORM public._staff_audit(
    'set_fee', 'platform_fee_catalog', trim(p_fee_key),
    jsonb_build_object('amount_sar', p_amount_sar)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_login_ad(
  p_title_ar text,
  p_title_en text,
  p_subtitle_ar text DEFAULT '',
  p_subtitle_en text DEFAULT '',
  p_image_url text DEFAULT NULL,
  p_link_url text DEFAULT NULL,
  p_id uuid DEFAULT NULL
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
  IF NOT coalesce((SELECT can_moderate FROM public.platform_staff WHERE user_id = v_uid), false)
     AND NOT coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_moderate');
  END IF;
  IF p_id IS NOT NULL THEN
    UPDATE public.ads SET
      title = coalesce(nullif(trim(p_title_ar), ''), title),
      title_ar = p_title_ar,
      title_en = p_title_en,
      subtitle_ar = p_subtitle_ar,
      subtitle_en = p_subtitle_en,
      image_url = nullif(trim(coalesce(p_image_url, '')), ''),
      link_url = nullif(trim(coalesce(p_link_url, '')), ''),
      show_on_web = true,
      show_on_app = true,
      is_active = true,
      deleted_at = NULL
    WHERE id = p_id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO public.ads (
      title, title_ar, title_en, subtitle_ar, subtitle_en,
      image_url, link_url, show_on_web, show_on_app, is_active
    ) VALUES (
      coalesce(nullif(trim(p_title_ar), ''), 'Ad'),
      p_title_ar, p_title_en, p_subtitle_ar, p_subtitle_en,
      nullif(trim(coalesce(p_image_url, '')), ''),
      nullif(trim(coalesce(p_link_url, '')), ''),
      true, true, true
    ) RETURNING id INTO v_id;
  END IF;
  PERFORM public._staff_audit('login_ad', 'ads', v_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_directory(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_directory(text, int) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_team_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_team_list() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_revoke_ops(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_revoke_ops(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_set_fee(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_set_fee(text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_login_ad(text, text, text, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_login_ad(text, text, text, text, text, text, uuid) TO authenticated;

ALTER TABLE public.ads
  ADD COLUMN IF NOT EXISTS title_ar text,
  ADD COLUMN IF NOT EXISTS title_en text,
  ADD COLUMN IF NOT EXISTS subtitle_ar text,
  ADD COLUMN IF NOT EXISTS subtitle_en text;

CREATE OR REPLACE FUNCTION public.platform_staff_reply_complaint(
  p_complaint_id uuid,
  p_reply text,
  p_status text DEFAULT 'awaiting_user'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_reply text := trim(coalesce(p_reply, ''));
  v_status text := lower(trim(coalesce(p_status, 'awaiting_user')));
  r public.regc_user_complaints%ROWTYPE;
  v_thread jsonb;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_support FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_support');
  END IF;
  IF length(v_reply) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reply_required');
  END IF;
  IF v_status NOT IN ('open', 'awaiting_user', 'escalated', 'resolved', 'closed') THEN
    v_status := 'awaiting_user';
  END IF;

  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  v_thread := coalesce(r.details->'chat_thread', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'role', 'staff',
      'text', v_reply,
      'at', now(),
      'by', v_staff
    )
  );

  UPDATE public.regc_user_complaints
  SET
    status = v_status,
    details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
      'admin_reply', v_reply,
      'admin_reply_at', to_jsonb(now()),
      'admin_reply_by', v_staff,
      'chat_thread', v_thread
    )
  WHERE id = p_complaint_id;

  PERFORM public._staff_audit(
    'support_reply', 'regc_user_complaints', p_complaint_id::text,
    jsonb_build_object('status', v_status)
  );

  BEGIN
    PERFORM public.workflow_create_notification(
      r.user_id,
      'support_ticket',
      'رد على تذكرة الدعم',
      v_reply,
      'complaint',
      p_complaint_id,
      jsonb_build_object(
        'title_ar', 'رد من دعم المنصة',
        'title_en', 'Support reply',
        'body_ar', v_reply,
        'body_en', v_reply
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_send_notice(
  p_user_id uuid,
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
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT can_support FROM public.platform_staff WHERE user_id = v_uid), false)
     AND NOT coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_support');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;
  BEGIN
    PERFORM public.workflow_create_notification(
      p_user_id,
      'ops_broadcast',
      coalesce(nullif(trim(p_title_ar), ''), 'إشعار المنصة'),
      coalesce(nullif(trim(p_body_ar), ''), coalesce(p_body_en, '')),
      'ops',
      NULL,
      jsonb_build_object(
        'title_ar', coalesce(p_title_ar, ''),
        'title_en', coalesce(p_title_en, ''),
        'body_ar', coalesce(p_body_ar, ''),
        'body_en', coalesce(p_body_en, '')
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'notify_failed');
  END;
  PERFORM public._staff_audit(
    'send_notice', 'in_app_notifications', p_user_id::text,
    jsonb_build_object('title_ar', p_title_ar)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_send_notice(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_send_notice(uuid, text, text, text, text) TO authenticated;

COMMIT;
