-- صلاحيات تشغيل إضافية: إعلانات، عروض، حظر، بث للفريق. المالك يملك الكل.
-- مساعد المدير = can_grant (يدير الأعضاء نيابة عن المالك دون أن يصبح مالكاً).

BEGIN;

ALTER TABLE public.platform_staff
  ADD COLUMN IF NOT EXISTS can_ads boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_promo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_ban boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_team_comms boolean NOT NULL DEFAULT false;

UPDATE public.platform_staff
SET can_ads = true,
    can_promo = true,
    can_ban = true,
    can_team_comms = true,
    can_grant = true,
    can_finance = true,
    can_moderate = true,
    can_support = true
WHERE coalesce(is_owner, false);

ALTER TABLE public.ads
  ADD COLUMN IF NOT EXISTS placement text NOT NULL DEFAULT 'login';

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
    'can_finance', r.can_finance OR coalesce(r.is_owner, false),
    'can_moderate', r.can_moderate OR coalesce(r.is_owner, false),
    'can_support', r.can_support OR coalesce(r.is_owner, false),
    'can_ads', coalesce(r.can_ads, false) OR coalesce(r.is_owner, false) OR coalesce(r.can_moderate, false),
    'can_promo', coalesce(r.can_promo, false) OR coalesce(r.is_owner, false) OR coalesce(r.can_finance, false),
    'can_ban', coalesce(r.can_ban, false) OR coalesce(r.is_owner, false) OR coalesce(r.can_moderate, false),
    'can_team_comms', coalesce(r.can_team_comms, false) OR coalesce(r.is_owner, false),
    'is_active', r.is_active
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
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
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
        'can_ads', s.can_ads,
        'can_promo', s.can_promo,
        'can_ban', s.can_ban,
        'can_team_comms', s.can_team_comms,
        'roles', s.roles
      ) ORDER BY s.is_owner DESC, up.username)
      FROM public.platform_staff s
      LEFT JOIN public.users_profiles up ON up.user_id = s.user_id
    ), '[]'::jsonb)
  );
END;
$$;

DROP FUNCTION IF EXISTS public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean);
DROP FUNCTION IF EXISTS public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean);

CREATE OR REPLACE FUNCTION public.platform_staff_grant_ops(
  p_user_id uuid,
  p_support boolean DEFAULT true,
  p_moderate boolean DEFAULT false,
  p_finance boolean DEFAULT false,
  p_grant boolean DEFAULT false,
  p_active boolean DEFAULT true,
  p_ads boolean DEFAULT false,
  p_promo boolean DEFAULT false,
  p_ban boolean DEFAULT false,
  p_team_comms boolean DEFAULT false
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
    RETURN jsonb_build_object('ok', false, 'error', 'owner_only_deputy');
  END IF;

  v_roles := '[]'::jsonb;
  IF p_support THEN v_roles := v_roles || '["support"]'::jsonb; END IF;
  IF p_moderate THEN v_roles := v_roles || '["compliance"]'::jsonb; END IF;
  IF p_finance THEN v_roles := v_roles || '["finance"]'::jsonb; END IF;
  IF p_grant THEN v_roles := v_roles || '["deputy"]'::jsonb; END IF;
  IF p_ads THEN v_roles := v_roles || '["ads"]'::jsonb; END IF;
  IF p_promo THEN v_roles := v_roles || '["promo"]'::jsonb; END IF;
  IF p_ban THEN v_roles := v_roles || '["ban"]'::jsonb; END IF;
  IF p_team_comms THEN v_roles := v_roles || '["team"]'::jsonb; END IF;

  INSERT INTO public.platform_staff (
    user_id, role, is_active, is_owner, can_grant,
    can_support, can_moderate, can_finance, roles,
    can_ads, can_promo, can_ban, can_team_comms
  ) VALUES (
    p_user_id,
    CASE WHEN p_grant THEN 'deputy' WHEN p_finance THEN 'finance' WHEN p_moderate THEN 'compliance' ELSE 'staff' END,
    coalesce(p_active, true),
    false,
    coalesce(p_grant, false),
    coalesce(p_support, true),
    coalesce(p_moderate, false),
    coalesce(p_finance, false),
    v_roles,
    coalesce(p_ads, false),
    coalesce(p_promo, false),
    coalesce(p_ban, false),
    coalesce(p_team_comms, false)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    is_active = excluded.is_active,
    can_support = excluded.can_support,
    can_moderate = excluded.can_moderate,
    can_finance = excluded.can_finance,
    can_ads = excluded.can_ads,
    can_promo = excluded.can_promo,
    can_ban = excluded.can_ban,
    can_team_comms = excluded.can_team_comms,
    can_grant = CASE
      WHEN public.platform_staff.is_owner THEN public.platform_staff.can_grant
      ELSE excluded.can_grant
    END,
    role = CASE WHEN public.platform_staff.is_owner THEN public.platform_staff.role ELSE excluded.role END,
    roles = excluded.roles;

  PERFORM public._staff_audit(
    'grant_ops', 'platform_staff', p_user_id::text,
    jsonb_build_object(
      'support', p_support, 'moderate', p_moderate, 'finance', p_finance,
      'deputy', p_grant, 'ads', p_ads, 'promo', p_promo, 'ban', p_ban,
      'team', p_team_comms, 'active', p_active
    )
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_ban_user(
  p_user_id uuid,
  p_reason text,
  p_ban_type text DEFAULT 'permanent',
  p_ban_until date DEFAULT NULL,
  p_can_join_other_orgs boolean DEFAULT true,
  p_blocks_app boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_ban FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_moderate FROM public.platform_staff WHERE user_id = v_staff), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_ban');
  END IF;
  IF coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = p_user_id), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_ban_owner');
  END IF;
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_user');
  END IF;

  INSERT INTO public.banned_accounts (
    user_id, banned_by, ban_reason, ban_type, ban_until, can_join_other_orgs, blocks_app
  ) VALUES (
    p_user_id, v_staff, nullif(trim(coalesce(p_reason, '')), ''),
    coalesce(nullif(trim(coalesce(p_ban_type, '')), ''), 'permanent'),
    p_ban_until, coalesce(p_can_join_other_orgs, true), coalesce(p_blocks_app, true)
  )
  ON CONFLICT (user_id) DO UPDATE SET
    banned_by = excluded.banned_by,
    ban_reason = excluded.ban_reason,
    ban_type = excluded.ban_type,
    ban_until = excluded.ban_until,
    can_join_other_orgs = excluded.can_join_other_orgs,
    blocks_app = excluded.blocks_app,
    lifted_at = NULL,
    lifted_by = NULL,
    created_at = now();

  PERFORM public._staff_audit('ban_user', 'banned_accounts', p_user_id::text, jsonb_build_object('reason', p_reason));
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_lift_ban(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_ban FROM public.platform_staff WHERE user_id = v_staff), false)
    OR coalesce((SELECT can_moderate FROM public.platform_staff WHERE user_id = v_staff), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_ban');
  END IF;
  UPDATE public.banned_accounts
  SET lifted_at = now(), lifted_by = v_staff
  WHERE user_id = p_user_id AND lifted_at IS NULL;
  PERFORM public._staff_audit('lift_ban', 'banned_accounts', p_user_id::text, '{}'::jsonb);
  RETURN jsonb_build_object('ok', true);
END;
$$;

DROP FUNCTION IF EXISTS public.platform_staff_upsert_login_ad(text, text, text, text, text, text, uuid);

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_login_ad(
  p_title_ar text,
  p_title_en text,
  p_subtitle_ar text DEFAULT '',
  p_subtitle_en text DEFAULT '',
  p_image_url text DEFAULT NULL,
  p_link_url text DEFAULT NULL,
  p_id uuid DEFAULT NULL,
  p_placement text DEFAULT 'login'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_place text := lower(trim(coalesce(p_placement, 'login')));
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_ads FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_moderate FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_ads');
  END IF;
  IF v_place NOT IN ('login', 'in_app', 'team', 'support_card') THEN
    v_place := 'login';
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
      placement = v_place,
      show_on_web = v_place IN ('login', 'in_app', 'support_card'),
      show_on_app = v_place IN ('in_app', 'support_card', 'login'),
      is_active = true,
      deleted_at = NULL
    WHERE id = p_id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO public.ads (
      title, title_ar, title_en, subtitle_ar, subtitle_en,
      image_url, link_url, show_on_web, show_on_app, is_active, placement
    ) VALUES (
      coalesce(nullif(trim(p_title_ar), ''), 'Ad'),
      p_title_ar, p_title_en, p_subtitle_ar, p_subtitle_en,
      nullif(trim(coalesce(p_image_url, '')), ''),
      nullif(trim(coalesce(p_link_url, '')), ''),
      v_place IN ('login', 'in_app', 'support_card'),
      v_place IN ('in_app', 'support_card', 'login'),
      true,
      v_place
    ) RETURNING id INTO v_id;
  END IF;
  PERFORM public._staff_audit('ops_ad', 'ads', v_id::text, jsonb_build_object('placement', v_place));
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_promo(
  p_code text,
  p_kind text DEFAULT 'percent_off',
  p_value numeric DEFAULT 0,
  p_title_ar text DEFAULT '',
  p_title_en text DEFAULT '',
  p_active boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_kind text := lower(trim(coalesce(p_kind, 'percent_off')));
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_promo FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_promo');
  END IF;
  IF length(v_code) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_required');
  END IF;
  IF v_kind NOT IN ('percent_off', 'fixed_off', 'trial_days', 'first_payment_bonus') THEN
    v_kind := 'percent_off';
  END IF;

  SELECT id INTO v_id FROM public.subscription_promotions WHERE lower(code) = lower(v_code);
  IF v_id IS NOT NULL THEN
    UPDATE public.subscription_promotions SET
      kind = v_kind,
      value = coalesce(p_value, 0),
      title_ar = p_title_ar,
      title_en = p_title_en,
      is_active = coalesce(p_active, true)
    WHERE id = v_id;
  ELSE
    INSERT INTO public.subscription_promotions (
      code, kind, value, title_ar, title_en, is_active
    ) VALUES (
      v_code, v_kind, coalesce(p_value, 0), p_title_ar, p_title_en, coalesce(p_active, true)
    ) RETURNING id INTO v_id;
  END IF;
  PERFORM public._staff_audit('upsert_promo', 'subscription_promotions', v_id::text, jsonb_build_object('code', v_code));
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_promos()
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
        'id', p.id,
        'code', p.code,
        'kind', p.kind,
        'value', p.value,
        'title_ar', p.title_ar,
        'title_en', p.title_en,
        'is_active', p.is_active
      ) ORDER BY p.created_at DESC)
      FROM public.subscription_promotions p
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_broadcast_team(
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
  r record;
  v_n int := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_team_comms FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_team');
  END IF;
  FOR r IN
    SELECT s.user_id FROM public.platform_staff s WHERE coalesce(s.is_active, true)
  LOOP
    BEGIN
      PERFORM public.workflow_create_notification(
        r.user_id,
        'ops_team',
        coalesce(nullif(trim(p_title_ar), ''), 'إشعار الفريق'),
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
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
  PERFORM public._staff_audit('broadcast_team', 'in_app_notifications', v_uid::text, jsonb_build_object('sent', v_n));
  RETURN jsonb_build_object('ok', true, 'sent', v_n);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_grant_ops(uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_login_ad(text, text, text, text, text, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_login_ad(text, text, text, text, text, text, uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_list_promos() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_promos() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_broadcast_team(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_broadcast_team(text, text, text, text) TO authenticated;

COMMIT;
