-- دعوات انضمام الفريق: هوية + جوال، صلاحية 72 ساعة، بدون QR/رمز فال للموظفين.

-- ---------------------------------------------------------------------------
-- 1) جدول الدعوات
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_team_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  invited_by_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  national_id text NOT NULL,
  mobile_local text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'expired', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '72 hours'),
  completed_at timestamptz,
  completed_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  sms_sent_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_org_team_invitations_org_status
  ON public.org_team_invitations (org_id, status, expires_at DESC);

CREATE INDEX IF NOT EXISTS idx_org_team_invitations_lookup
  ON public.org_team_invitations (national_id, mobile_local)
  WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_team_invitations_pending_triple
  ON public.org_team_invitations (org_id, national_id, mobile_local)
  WHERE status = 'pending';

ALTER TABLE public.org_team_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_team_invitations_owner_select ON public.org_team_invitations;
CREATE POLICY org_team_invitations_owner_select
  ON public.org_team_invitations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = org_team_invitations.org_id
        AND o.owner_user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 2) أدوات تطبيع
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.norm_digits10(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT left(regexp_replace(coalesce(p_raw, ''), '\D', '', 'g'), 10);
$$;

CREATE OR REPLACE FUNCTION public.norm_saudi_mobile_local(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  d text := regexp_replace(coalesce(p_raw, ''), '\D', '', 'g');
BEGIN
  IF length(d) = 12 AND left(d, 3) = '966' AND substring(d, 4, 1) = '5' THEN
    d := '0' || substring(d, 4);
  ELSIF length(d) = 11 AND left(d, 2) = '05' THEN
    d := d;
  ELSIF length(d) = 9 AND left(d, 1) = '5' THEN
    d := '0' || d;
  END IF;
  IF length(d) = 10 AND left(d, 2) = '05' THEN
    RETURN d;
  END IF;
  RETURN '';
END;
$$;

CREATE OR REPLACE FUNCTION public.org_expire_stale_team_invitations()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int;
BEGIN
  UPDATE public.org_team_invitations
  SET status = 'expired', updated_at = now()
  WHERE status = 'pending'
    AND expires_at < now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) إنشاء دعوة (المالك / المسوّق)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_create_team_invitation(
  p_national_id text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_nid text := public.norm_digits10(p_national_id);
  v_mob text := public.norm_saudi_mobile_local(p_mobile);
  v_lim int;
  v_cnt int;
  v_pending int;
  v_inv uuid;
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  PERFORM public.org_expire_stale_team_invitations();

  IF length(v_nid) <> 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_national_id');
  END IF;
  IF length(v_mob) <> 10 OR left(v_mob, 2) <> '05' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_mobile');
  END IF;

  SELECT id, owner_user_id INTO v_org, v_owner
  FROM public.org_units
  WHERE owner_user_id = v_uid
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF NOT public.org_owner_has_active_subscription(v_org) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_subscription_required');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.users_profiles up
    WHERE up.username = v_nid OR up.national_id = v_nid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'national_id_already_registered');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_team_invitations i
    WHERE i.org_id = v_org
      AND i.status = 'pending'
      AND i.national_id = v_nid
      AND i.mobile_local = v_mob
      AND i.expires_at > now()
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'duplicate_pending');
  END IF;

  v_lim := public.org_effective_seat_limit(v_org);
  v_cnt := public.org_current_member_count(v_org);
  SELECT count(*)::int INTO v_pending
  FROM public.org_team_invitations i
  WHERE i.org_id = v_org
    AND i.status = 'pending'
    AND i.expires_at > now();

  IF (v_cnt + v_pending) >= v_lim THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached', 'limit', v_lim);
  END IF;

  INSERT INTO public.org_team_invitations (
    org_id, invited_by_user_id, national_id, mobile_local, status, expires_at
  ) VALUES (
    v_org, v_uid, v_nid, v_mob, 'pending', now() + interval '72 hours'
  )
  RETURNING id INTO v_inv;

  INSERT INTO public.org_activity_log (org_id, actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (
    v_org, v_uid, 'team_invitation.created', 'org_team_invitation', v_inv::text,
    jsonb_build_object('national_id', v_nid, 'mobile_local', v_mob)
  );

  PERFORM public._inapp_enqueue_for_user(
    v_uid,
    'org_team_invitation_created',
    'تم إرسال طلب الانضمام',
    'أُضيف طلب انضمام عضو جديد (هوية وجوال). سيُكمل العضو التسجيل خلال 72 ساعة.',
    jsonb_build_object(
      'title_ar', 'طلب انضمام عضو',
      'title_en', 'Team member invitation sent',
      'body_ar', 'راجع طلبات الانضمام في «إدارتي».',
      'body_en', 'Review join requests in My desk.',
      'org_id', v_org::text,
      'invitation_id', v_inv::text
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_inv,
    'expires_at', (SELECT expires_at FROM public.org_team_invitations WHERE id = v_inv)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) قائمة الدعوات للمالك
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_list_team_invitations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  PERFORM public.org_expire_stale_team_invitations();

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      i.id AS invitation_id,
      i.national_id,
      i.mobile_local,
      i.status,
      i.created_at,
      i.expires_at,
      i.completed_at,
      i.completed_user_id
    FROM public.org_team_invitations i
    WHERE i.org_id = v_org
      AND i.status IN ('pending', 'completed')
    ORDER BY i.created_at DESC
    LIMIT 200
  ) t;

  RETURN v_rows;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) تعديل دعوة معلّقة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_update_team_invitation(
  p_invitation_id uuid,
  p_national_id text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_nid text := public.norm_digits10(p_national_id);
  v_mob text := public.norm_saudi_mobile_local(p_mobile);
  v_row public.org_team_invitations%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF length(v_nid) <> 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_national_id');
  END IF;
  IF length(v_mob) <> 10 OR left(v_mob, 2) <> '05' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_mobile');
  END IF;

  SELECT * INTO v_row FROM public.org_team_invitations WHERE id = p_invitation_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  SELECT id INTO v_org FROM public.org_units
  WHERE id = v_row.org_id AND owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF v_row.status <> 'pending' OR v_row.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_pending');
  END IF;

  UPDATE public.org_team_invitations
  SET
    national_id = v_nid,
    mobile_local = v_mob,
    updated_at = now()
  WHERE id = p_invitation_id;

  INSERT INTO public.org_activity_log (org_id, actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (
    v_org, v_uid, 'team_invitation.updated', 'org_team_invitation', p_invitation_id::text,
    jsonb_build_object('national_id', v_nid, 'mobile_local', v_mob)
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) التحقق قبل التسجيل (anon + authenticated)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_verify_team_invitation(
  p_national_id text,
  p_mobile text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nid text := public.norm_digits10(p_national_id);
  v_mob text := public.norm_saudi_mobile_local(p_mobile);
  v_inv public.org_team_invitations%ROWTYPE;
  v_inviter uuid;
  v_name_ar text;
  v_name_en text;
  v_phone text;
  v_org_type text;
BEGIN
  PERFORM public.org_expire_stale_team_invitations();

  IF length(v_nid) <> 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_national_id');
  END IF;
  IF length(v_mob) <> 10 OR left(v_mob, 2) <> '05' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_mobile');
  END IF;

  SELECT * INTO v_inv
  FROM public.org_team_invitations i
  WHERE i.status = 'pending'
    AND i.national_id = v_nid
    AND i.mobile_local = v_mob
    AND i.expires_at > now()
  ORDER BY i.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'no_match',
      'message_ar', 'عليك التواصل مع المسوق أو مدير المنشأة لتعديل بياناتك ثم العودة لإكمال إنشاء الحساب.',
      'message_en', 'Contact your manager to update your invitation details, then try again.'
    );
  END IF;

  v_inviter := v_inv.invited_by_user_id;

  SELECT
    trim(coalesce(
      nullif(concat_ws(' ', first_name_ar, second_name_ar, third_name_ar, fourth_name_ar), ''),
      full_name_ar,
      username,
      ''
    )),
    trim(coalesce(
      nullif(concat_ws(' ', first_name_en, second_name_en, third_name_en, fourth_name_en), ''),
      full_name_en,
      full_name,
      username,
      ''
    )),
    coalesce(phone, '')
  INTO v_name_ar, v_name_en, v_phone
  FROM public.users_profiles
  WHERE user_id = v_inviter
  LIMIT 1;

  IF NOT public.org_owner_has_active_subscription(v_inv.org_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_subscription_inactive');
  END IF;

  IF public.org_current_member_count(v_inv.org_id) >= public.org_effective_seat_limit(v_inv.org_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached');
  END IF;

  SELECT account_type::text INTO v_org_type
  FROM public.org_units WHERE id = v_inv.org_id LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_inv.id,
    'org_id', v_inv.org_id,
    'org_account_type', coalesce(nullif(trim(v_org_type), ''), 'office'),
    'inviter_user_id', v_inviter,
    'inviter_full_name_ar', v_name_ar,
    'inviter_full_name_en', v_name_en,
    'inviter_phone', v_phone,
    'requested_at', v_inv.created_at,
    'expires_at', v_inv.expires_at
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) إكمال الانضمام بعد إنشاء الحساب
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_complete_team_invitation(
  p_invitation_id uuid,
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_inv public.org_team_invitations%ROWTYPE;
  v_org_type text;
  v_owner uuid;
  v_lim int;
  v_cnt int;
  v_perm jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  PERFORM public.org_expire_stale_team_invitations();

  SELECT * INTO v_inv
  FROM public.org_team_invitations
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF v_inv.status <> 'pending' OR v_inv.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invitation_not_active');
  END IF;

  IF v_inv.national_id IS DISTINCT FROM (
    SELECT coalesce(nullif(trim(username), ''), national_id)
    FROM public.users_profiles WHERE user_id = v_uid LIMIT 1
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'national_id_mismatch');
  END IF;

  IF public.norm_saudi_mobile_local(
    coalesce((SELECT phone FROM public.users_profiles WHERE user_id = v_uid LIMIT 1), '')
  ) IS DISTINCT FROM v_inv.mobile_local THEN
    RETURN jsonb_build_object('ok', false, 'error', 'mobile_mismatch');
  END IF;

  IF NOT public.org_owner_has_active_subscription(v_inv.org_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_subscription_inactive');
  END IF;

  v_lim := public.org_effective_seat_limit(v_inv.org_id);
  v_cnt := public.org_current_member_count(v_inv.org_id);
  IF v_cnt >= v_lim THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_memberships m
    WHERE m.user_id = v_uid AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_member');
  END IF;

  SELECT account_type::text, owner_user_id
  INTO v_org_type, v_owner
  FROM public.org_units
  WHERE id = v_inv.org_id
  LIMIT 1;

  v_perm := public.org_default_member_permissions();

  INSERT INTO public.org_memberships (
    org_id, user_id, member_role, permissions, status, invited_by_user_id
  ) VALUES (
    v_inv.org_id, v_uid, 'member', v_perm, 'active', v_inv.invited_by_user_id
  )
  ON CONFLICT (user_id) DO UPDATE SET
    org_id = excluded.org_id,
    member_role = 'member',
    permissions = excluded.permissions,
    status = 'active',
    invited_by_user_id = excluded.invited_by_user_id;

  UPDATE public.users_profiles
  SET org_id = v_inv.org_id,
      account_type = coalesce(nullif(trim(v_org_type), ''), account_type)
  WHERE user_id = v_uid;

  UPDATE public.org_team_invitations
  SET
    status = 'completed',
    completed_at = now(),
    completed_user_id = v_uid,
    updated_at = now()
  WHERE id = p_invitation_id;

  INSERT INTO public.org_activity_log (org_id, actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (
    v_inv.org_id, v_uid, 'team_invitation.completed', 'user', v_uid::text,
    jsonb_build_object('invitation_id', p_invitation_id)
  );

  IF v_owner IS NOT NULL THEN
    PERFORM public._inapp_enqueue_for_user(
      v_owner,
      'org_team_member_joined',
      'انضم عضو جديد',
      'أكمل العضو إنشاء حسابه وانضم لفريقك.',
      jsonb_build_object(
        'title_ar', 'انضمام عضو للفريق',
        'title_en', 'New team member joined',
        'body_ar', 'راجع إدارة الفريق في «إدارتي».',
        'body_en', 'Review team management in My desk.',
        'org_id', v_inv.org_id::text,
        'user_id', v_uid::text
      )
    );
  END IF;

  PERFORM public._inapp_enqueue_for_user(
    v_inv.invited_by_user_id,
    'org_team_member_joined',
    'تم انضمامك للفريق',
    'أصبح حسابك مرتبطاً بالمنشأة.',
    jsonb_build_object(
      'title_ar', 'مرحباً بك في الفريق',
      'title_en', 'Welcome to the team',
      'org_id', v_inv.org_id::text
    )
  );

  RETURN jsonb_build_object('ok', true, 'org_id', v_inv.org_id);
END;
$$;

-- استبدال قائمة الطلبات القديمة (بعد تسجيل الدخول) بقائمة الدعوات المعلّقة
DROP FUNCTION IF EXISTS public.org_list_pending_join_requests();

CREATE OR REPLACE FUNCTION public.org_list_pending_join_requests()
RETURNS TABLE (
  request_id uuid,
  national_id text,
  mobile_local text,
  created_at timestamptz,
  expires_at timestamptz,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.org_expire_stale_team_invitations();

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    i.id,
    i.national_id,
    i.mobile_local,
    i.created_at,
    i.expires_at,
    i.status
  FROM public.org_team_invitations i
  WHERE i.org_id = v_org
    AND i.status = 'pending'
    AND i.expires_at > now()
  ORDER BY i.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_list_pending_join_requests() TO authenticated;

GRANT EXECUTE ON FUNCTION public.org_create_team_invitation(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_list_team_invitations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_update_team_invitation(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_verify_team_invitation(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.org_complete_team_invitation(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_expire_stale_team_invitations() TO authenticated;

