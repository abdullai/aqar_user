-- =============================================================================
-- توسعة منشآت: رخصة فال المعروضة، صلاحيات JSON موحّدة، حظر، مغادرة، إشعارات
-- يمدّد الجداول الحالية (org_units / org_memberships / org_join_requests)
-- بدلاً من إنشاء organizations منفصلة.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) أعمدة org_units
-- ---------------------------------------------------------------------------
ALTER TABLE public.org_units
  ADD COLUMN IF NOT EXISTS fal_public_code text,
  ADD COLUMN IF NOT EXISTS fal_license_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS display_name_ar text,
  ADD COLUMN IF NOT EXISTS display_name_en text,
  ADD COLUMN IF NOT EXISTS description_ar text,
  ADD COLUMN IF NOT EXISTS description_en text,
  ADD COLUMN IF NOT EXISTS address_ar text,
  ADD COLUMN IF NOT EXISTS address_en text,
  ADD COLUMN IF NOT EXISTS org_public_email text,
  ADD COLUMN IF NOT EXISTS org_public_phone text,
  ADD COLUMN IF NOT EXISTS logo_url text,
  ADD COLUMN IF NOT EXISTS cover_url text,
  ADD COLUMN IF NOT EXISTS extra_seats_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS uq_org_units_fal_public_code
  ON public.org_units (fal_public_code)
  WHERE fal_public_code IS NOT NULL AND length(trim(fal_public_code)) > 0;

-- ---------------------------------------------------------------------------
-- 2) توليد رخصة معروضة FAL-XXXX-XXXX (أحرف أرقام)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.gen_org_fal_public_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  part text;
  fal_full text;
  n int := 0;
BEGIN
  LOOP
    part := '';
    FOR i IN 1..4 LOOP
      part := part || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    END LOOP;
    fal_full := 'FAL-' || part || '-' ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1);
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.org_units WHERE fal_public_code = fal_full
    );
    n := n + 1;
    IF n > 100 THEN
      RAISE EXCEPTION 'could not allocate fal_public_code';
    END IF;
  END LOOP;
  RETURN fal_full;
END;
$$;

CREATE OR REPLACE FUNCTION public.org_units_assign_fal_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.fal_public_code IS NULL OR length(trim(NEW.fal_public_code)) < 8 THEN
    NEW.fal_public_code := public.gen_org_fal_public_code();
  END IF;
  IF NEW.fal_license_expires_at IS NULL THEN
    NEW.fal_license_expires_at := (now() + interval '1 year');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_org_units_fal_public_code ON public.org_units;
CREATE TRIGGER tr_org_units_fal_public_code
  BEFORE INSERT ON public.org_units
  FOR EACH ROW
  EXECUTE FUNCTION public.org_units_assign_fal_public_code();

UPDATE public.org_units ou
SET
  fal_public_code = public.gen_org_fal_public_code(),
  fal_license_expires_at = coalesce(ou.fal_license_expires_at, now() + interval '1 year')
WHERE ou.fal_public_code IS NULL OR length(trim(ou.fal_public_code)) < 8;

-- ---------------------------------------------------------------------------
-- 3) محظورو المنشأة + سجل المغادرين + طلبات الخروج
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.org_banned_users (
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  PRIMARY KEY (org_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_banned_org ON public.org_banned_users (org_id);

ALTER TABLE public.org_banned_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_banned_select_owner ON public.org_banned_users;
CREATE POLICY org_banned_select_owner ON public.org_banned_users
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = org_banned_users.org_id AND o.owner_user_id = auth.uid()
    )
    OR user_id = auth.uid()
  );

CREATE TABLE IF NOT EXISTS public.org_member_alumni (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  left_at timestamptz NOT NULL DEFAULT now(),
  note text
);

CREATE INDEX IF NOT EXISTS idx_org_alumni_org ON public.org_member_alumni (org_id);

ALTER TABLE public.org_member_alumni ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_alumni_select_owner ON public.org_member_alumni;
CREATE POLICY org_alumni_select_owner ON public.org_member_alumni
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = org_member_alumni.org_id AND o.owner_user_id = auth.uid()
    )
  );

CREATE TABLE IF NOT EXISTS public.org_leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.org_units (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_org_leave_org_status ON public.org_leave_requests (org_id, status);

ALTER TABLE public.org_leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_leave_select ON public.org_leave_requests;
CREATE POLICY org_leave_select ON public.org_leave_requests
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.org_units o
      WHERE o.id = org_leave_requests.org_id AND o.owner_user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4) org_join_requests — رسالة المتقدم + سبب الرفض
-- ---------------------------------------------------------------------------
ALTER TABLE public.org_join_requests
  ADD COLUMN IF NOT EXISTS applicant_message text,
  ADD COLUMN IF NOT EXISTS reject_reason text;

-- ---------------------------------------------------------------------------
-- 5) تحديث حدود المقاعد + مؤسسة = 6 أعضاء
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_my_org_unit()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_type text;
  v_org uuid;
  v_limit int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT lower(trim(account_type::text)) INTO v_type
  FROM users_profiles
  WHERE user_id = v_uid;

  IF v_type IS NULL OR v_type NOT IN ('office', 'institution', 'company') THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NOT NULL THEN
    UPDATE users_profiles SET org_id = v_org WHERE user_id = v_uid AND (org_id IS DISTINCT FROM v_org);
    RETURN v_org;
  END IF;

  v_limit := CASE v_type
    WHEN 'office' THEN 3
    WHEN 'institution' THEN 6
    ELSE 12
  END;

  INSERT INTO org_units (owner_user_id, account_type, base_seat_limit)
  VALUES (v_uid, v_type, v_limit)
  RETURNING id INTO v_org;

  INSERT INTO org_memberships (org_id, user_id, member_role, permissions, status)
  VALUES (
    v_org,
    v_uid,
    'owner',
    '{"manage_team": true, "add_properties": true, "add_ads": true, "view_market": true, "view_profile": true, "access_chat": true, "edit_org_settings": true, "view_analytics": true, "desk": true, "middle_nav": true}'::jsonb,
    'active'
  );

  UPDATE users_profiles SET org_id = v_org WHERE user_id = v_uid;

  RETURN v_org;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) صلاحيات افتراضية للعضو الجديد
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_default_member_permissions()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'manage_team', false,
    'add_properties', false,
    'add_ads', false,
    'view_market', false,
    'view_profile', true,
    'access_chat', true,
    'edit_org_settings', false,
    'view_analytics', false,
    'desk', false,
    'middle_nav', false
  );
$$;

-- ---------------------------------------------------------------------------
-- 7) my_org_context — يعرض صلاحيات العضو
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_org_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_owner uuid;
  v_perm jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'org_id', null,
      'member_role', null,
      'is_owner', false,
      'permissions', null
    );
  END IF;

  SELECT m.org_id, m.member_role, m.permissions
  INTO v_org, v_role, v_perm
  FROM org_memberships m
  WHERE m.user_id = v_uid AND m.status = 'active'
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object(
      'org_id', null,
      'member_role', null,
      'is_owner', false,
      'permissions', null
    );
  END IF;

  SELECT owner_user_id INTO v_owner FROM org_units WHERE id = v_org LIMIT 1;

  RETURN jsonb_build_object(
    'org_id', v_org,
    'member_role', v_role,
    'is_owner', (v_owner = v_uid),
    'permissions', coalesce(v_perm, '{}'::jsonb)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8) إشعار المالك عند طلب انضمام (صف in_app_notifications)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._inapp_enqueue_for_user(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uname text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;
  SELECT username::text INTO uname FROM users_profiles WHERE user_id = p_user_id LIMIT 1;
  INSERT INTO public.in_app_notifications (
    username,
    user_id,
    type,
    title,
    body,
    data,
    is_read
  ) VALUES (
    coalesce(nullif(trim(uname), ''), 'user'),
    p_user_id,
    coalesce(nullif(trim(p_type), ''), 'org_join'),
    left(coalesce(p_title, ''), 200),
    left(coalesce(p_body, ''), 2000),
    coalesce(p_data, '{}'::jsonb),
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.tr_org_join_requests_notify_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;
  SELECT owner_user_id INTO v_owner FROM org_units WHERE id = NEW.org_id LIMIT 1;
  IF v_owner IS NOT NULL THEN
    PERFORM public._inapp_enqueue_for_user(
      v_owner,
      'org_join_request',
      'طلب انضمام جديد',
      'وصل طلب انضمام جديد إلى منشأتك.',
      jsonb_build_object(
        'title_ar', 'طلب انضمام جديد',
        'title_en', 'New join request',
        'body_ar', 'راجع طلبات الانضمام في «إدارتي».',
        'body_en', 'Review join requests in My desk.',
        'org_id', NEW.org_id::text,
        'request_id', NEW.id::text
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_org_join_requests_notify_owner ON public.org_join_requests;
CREATE TRIGGER tr_org_join_requests_notify_owner
  AFTER INSERT ON public.org_join_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_org_join_requests_notify_owner();

-- ---------------------------------------------------------------------------
-- 9) تقديم طلب بالمعرف + رسالة + تحقق من الحظر
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_submit_join_request_by_org(
  p_org_id uuid,
  p_message text DEFAULT NULL,
  p_verification_request_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF p_org_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_org');
  END IF;

  SELECT id INTO v_org FROM org_units WHERE id = p_org_id LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_org');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_banned_users b
    WHERE b.org_id = v_org AND b.user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'banned_from_org');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_memberships m
    WHERE m.user_id = v_uid AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_member');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_join_requests j
    WHERE j.applicant_user_id = v_uid AND j.status = 'pending'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_pending');
  END IF;

  INSERT INTO org_join_requests (
    org_id,
    applicant_user_id,
    verification_request_id,
    status,
    applicant_message
  ) VALUES (
    v_org,
    v_uid,
    p_verification_request_id,
    'pending',
    nullif(trim(coalesce(p_message, '')), '')
  );

  RETURN jsonb_build_object('ok', true, 'org_id', v_org);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_submit_join_request_by_org(uuid, text, bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 10) تصفح المنشآت العامة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_browse_public(limit_n int DEFAULT 40)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  lim int := greatest(1, least(coalesce(limit_n, 40), 100));
BEGIN
  RETURN (
    SELECT coalesce(jsonb_agg(sub.j), '[]'::jsonb)
    FROM (
      SELECT jsonb_build_object(
        'id', o.id,
        'account_type', o.account_type,
        'display_name_ar', coalesce(nullif(trim(o.display_name_ar), ''), ''),
        'display_name_en', coalesce(nullif(trim(o.display_name_en), ''), ''),
        'description_ar', coalesce(nullif(trim(o.description_ar), ''), ''),
        'description_en', coalesce(nullif(trim(o.description_en), ''), ''),
        'logo_url', coalesce(o.logo_url, ''),
        'fal_public_code', coalesce(o.fal_public_code, ''),
        'member_count', coalesce(public.org_current_member_count(o.id), 0),
        'seat_limit', coalesce(public.org_effective_seat_limit(o.id), 0)
      ) AS j
      FROM org_units o
      ORDER BY o.created_at DESC
      LIMIT lim
    ) sub
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_browse_public(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_browse_public(int) TO anon;

-- ---------------------------------------------------------------------------
-- 11) ملف عام للمنشأة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_public_profile(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o record;
BEGIN
  IF p_org_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO o FROM org_units WHERE id = p_org_id LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'id', o.id,
    'account_type', o.account_type,
    'display_name_ar', coalesce(o.display_name_ar, ''),
    'display_name_en', coalesce(o.display_name_en, ''),
    'description_ar', coalesce(o.description_ar, ''),
    'description_en', coalesce(o.description_en, ''),
    'address_ar', coalesce(o.address_ar, ''),
    'address_en', coalesce(o.address_en, ''),
    'org_public_email', coalesce(o.org_public_email, ''),
    'org_public_phone', coalesce(o.org_public_phone, ''),
    'logo_url', coalesce(o.logo_url, ''),
    'cover_url', coalesce(o.cover_url, ''),
    'fal_public_code', coalesce(o.fal_public_code, ''),
    'fal_license_expires_at', o.fal_license_expires_at,
    'member_count', public.org_current_member_count(o.id),
    'seat_limit', public.org_effective_seat_limit(o.id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_public_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_public_profile(uuid) TO anon;

-- ---------------------------------------------------------------------------
-- 12) تحديث بيانات المنشأة (المالك فقط)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_update_profile(
  p_patch jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'not_org_owner';
  END IF;

  UPDATE org_units SET
    display_name_ar = coalesce(nullif(trim(p_patch->>'display_name_ar'), ''), display_name_ar),
    display_name_en = coalesce(nullif(trim(p_patch->>'display_name_en'), ''), display_name_en),
    description_ar = coalesce(nullif(trim(p_patch->>'description_ar'), ''), description_ar),
    description_en = coalesce(nullif(trim(p_patch->>'description_en'), ''), description_en),
    address_ar = coalesce(nullif(trim(p_patch->>'address_ar'), ''), address_ar),
    address_en = coalesce(nullif(trim(p_patch->>'address_en'), ''), address_en),
    org_public_email = coalesce(nullif(trim(p_patch->>'org_public_email'), ''), org_public_email),
    org_public_phone = coalesce(nullif(trim(p_patch->>'org_public_phone'), ''), org_public_phone),
    logo_url = coalesce(nullif(trim(p_patch->>'logo_url'), ''), logo_url),
    cover_url = coalesce(nullif(trim(p_patch->>'cover_url'), ''), cover_url),
    updated_at = now()
  WHERE id = v_org;

  RETURN public.org_public_profile(v_org);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_update_profile(jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 13) تجديد رخصة فال المعروضة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_renew_fal_license()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'not_org_owner';
  END IF;
  v_code := public.gen_org_fal_public_code();
  UPDATE org_units SET
    fal_public_code = v_code,
    fal_license_expires_at = now() + interval '1 year',
    updated_at = now()
  WHERE id = v_org;
  RETURN jsonb_build_object('ok', true, 'fal_public_code', v_code);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_renew_fal_license() TO authenticated;

-- ---------------------------------------------------------------------------
-- 14) شراء مقاعد إضافية (بسيط: purchased_extra_seats += n حتى انتهاء)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_purchase_extra_seats(
  p_extra int,
  p_days int DEFAULT 365
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  ex int := greatest(0, least(coalesce(p_extra, 0), 50));
  days int := greatest(1, least(coalesce(p_days, 365), 3650));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'not_org_owner';
  END IF;
  IF ex <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_count');
  END IF;
  UPDATE org_units SET
    purchased_extra_seats = purchased_extra_seats + ex,
    extra_seats_expires_at = now() + make_interval(days => days),
    updated_at = now()
  WHERE id = v_org;
  RETURN jsonb_build_object('ok', true, 'purchased_extra_seats', ex);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_purchase_extra_seats(int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- 15) تعديل org_effective_seat_limit لاحترام انتهاء المقاعد الإضافية
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_effective_seat_limit(p_org_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT base_seat_limit + CASE
    WHEN extra_seats_expires_at IS NOT NULL AND extra_seats_expires_at > now()
      THEN purchased_extra_seats
    ELSE 0
  END
  FROM org_units
  WHERE id = p_org_id;
$$;

-- ---------------------------------------------------------------------------
-- 16) قبول/رفض الطلب — حظر عند الرفض + صلاحيات افتراضية
-- ---------------------------------------------------------------------------
-- إرجاع/توقيع جديد: لا يمكن CREATE OR REPLACE عند اختلاف قائمة المعاملات أو RETURNS TABLE
DROP FUNCTION IF EXISTS public.org_decide_join_request(uuid, boolean, jsonb);
DROP FUNCTION IF EXISTS public.org_decide_join_request(uuid, boolean, jsonb, text);

CREATE OR REPLACE FUNCTION public.org_decide_join_request(
  p_request_id uuid,
  p_approve boolean,
  p_permissions jsonb DEFAULT '{}'::jsonb,
  p_reject_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
  v_req org_join_requests%ROWTYPE;
  v_lim int;
  v_cnt int;
  v_perm jsonb;
BEGIN
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  SELECT * INTO v_req FROM org_join_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF v_req.status IS DISTINCT FROM 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_pending');
  END IF;

  SELECT id INTO v_org
  FROM org_units
  WHERE id = v_req.org_id AND owner_user_id = v_owner
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF NOT p_approve THEN
    UPDATE org_join_requests SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner,
      reject_reason = nullif(trim(coalesce(p_reject_reason, '')), '')
    WHERE id = p_request_id;

    INSERT INTO org_banned_users (org_id, user_id, reason, created_by_user_id)
    VALUES (
      v_org,
      v_req.applicant_user_id,
      nullif(trim(coalesce(p_reject_reason, '')), ''),
      v_owner
    )
    ON CONFLICT (org_id, user_id) DO UPDATE SET
      reason = excluded.reason,
      created_at = now(),
      created_by_user_id = excluded.created_by_user_id;

    PERFORM public._inapp_enqueue_for_user(
      v_req.applicant_user_id,
      'org_join_rejected',
      'تم رفض طلب الانضمام',
      coalesce(nullif(trim(p_reject_reason), ''), 'لم تتم الموافقة على طلبك.'),
      jsonb_build_object(
        'title_ar', 'رفض طلب الانضمام',
        'title_en', 'Join request declined',
        'body_ar', coalesce(nullif(trim(p_reject_reason), ''), 'لم تتم الموافقة.'),
        'body_en', coalesce(nullif(trim(p_reject_reason), ''), 'Your request was declined.'),
        'org_id', v_org::text
      )
    );

    RETURN jsonb_build_object('ok', true, 'approved', false);
  END IF;

  v_lim := public.org_effective_seat_limit(v_org);
  v_cnt := public.org_current_member_count(v_org);
  IF v_cnt >= v_lim THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_memberships WHERE user_id = v_req.applicant_user_id
  ) THEN
    UPDATE org_join_requests SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner
    WHERE id = p_request_id;
    RETURN jsonb_build_object('ok', false, 'error', 'already_member_conflict');
  END IF;

  v_perm := public.org_default_member_permissions()
    || coalesce(p_permissions, '{}'::jsonb);

  INSERT INTO org_memberships (
    org_id, user_id, member_role, permissions, status, invited_by_user_id
  ) VALUES (
    v_org, v_req.applicant_user_id, 'member', v_perm, 'active', v_owner
  );

  UPDATE users_profiles SET org_id = v_org WHERE user_id = v_req.applicant_user_id;

  UPDATE org_join_requests SET
    status = 'approved',
    decided_at = now(),
    decided_by_user_id = v_owner
  WHERE id = p_request_id;

  PERFORM public._inapp_enqueue_for_user(
    v_req.applicant_user_id,
    'org_join_approved',
    'تم قبولك في المنشأة',
    'أصبحت عضواً نشطاً.',
    jsonb_build_object(
      'title_ar', 'قبول في المنشأة',
      'title_en', 'Accepted to organization',
      'body_ar', 'يمكنك الآن استخدام ميزات الفريق حسب الصلاحيات.',
      'body_en', 'You can now use team features per your permissions.',
      'org_id', v_org::text
    )
  );

  RETURN jsonb_build_object('ok', true, 'approved', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_decide_join_request(uuid, boolean, jsonb, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 17) قائمة الطلبات المعلقة — تتضمّن رسالة المتقدم
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.org_list_pending_join_requests();

CREATE OR REPLACE FUNCTION public.org_list_pending_join_requests()
RETURNS TABLE (
  request_id uuid,
  applicant_user_id uuid,
  created_at timestamptz,
  verification_request_id bigint,
  applicant_message text
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

  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT j.id, j.applicant_user_id, j.created_at, j.verification_request_id, j.applicant_message
  FROM org_join_requests j
  WHERE j.org_id = v_org AND j.status = 'pending'
  ORDER BY j.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_list_pending_join_requests() TO authenticated;

-- ---------------------------------------------------------------------------
-- 18) طلب مغادرة + قرار المالك
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_submit_leave_request()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  SELECT org_id INTO v_org
  FROM org_memberships
  WHERE user_id = v_uid AND status = 'active' AND member_role = 'member'
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_member');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_leave_requests lr
    WHERE lr.org_id = v_org AND lr.user_id = v_uid AND lr.status = 'pending'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_pending');
  END IF;

  INSERT INTO org_leave_requests (org_id, user_id, status)
  VALUES (v_org, v_uid, 'pending');

  PERFORM public._inapp_enqueue_for_user(
    (SELECT owner_user_id FROM org_units WHERE id = v_org LIMIT 1),
    'org_leave_request',
    'طلب مغادرة فريق',
    'طلب أحد الأعضاء مغادرة المنشأة.',
    jsonb_build_object(
      'title_ar', 'طلب مغادرة',
      'title_en', 'Leave request',
      'org_id', v_org::text
    )
  );

  RETURN jsonb_build_object('ok', true, 'org_id', v_org);
END;
$$;

CREATE OR REPLACE FUNCTION public.org_decide_leave_request(
  p_request_id uuid,
  p_approve boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
  r org_leave_requests%ROWTYPE;
BEGIN
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  SELECT * INTO r FROM org_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF r.status IS DISTINCT FROM 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_pending');
  END IF;

  SELECT id INTO v_org FROM org_units WHERE id = r.org_id AND owner_user_id = v_owner LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF NOT p_approve THEN
    UPDATE org_leave_requests SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner
    WHERE id = p_request_id;

    PERFORM public._inapp_enqueue_for_user(
      r.user_id,
      'org_leave_rejected',
      'تم رفض طلب المغادرة',
      'ما زلت عضواً في الفريق.',
      '{}'::jsonb
    );

    RETURN jsonb_build_object('ok', true, 'approved', false);
  END IF;

  DELETE FROM org_memberships
  WHERE org_id = v_org AND user_id = r.user_id AND member_role = 'member';

  UPDATE users_profiles SET org_id = NULL
  WHERE user_id = r.user_id AND org_id IS NOT DISTINCT FROM v_org;

  INSERT INTO org_member_alumni (org_id, user_id, note)
  VALUES (v_org, r.user_id, 'leave_approved');

  UPDATE org_leave_requests SET
    status = 'approved',
    decided_at = now(),
    decided_by_user_id = v_owner
  WHERE id = p_request_id;

  PERFORM public._inapp_enqueue_for_user(
    r.user_id,
    'org_leave_approved',
    'تمت الموافقة على مغادرتك',
    'يمكنك الانضمام لمنشأة أخرى.',
    jsonb_build_object('org_id', v_org::text)
  );

  RETURN jsonb_build_object('ok', true, 'approved', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_submit_leave_request() TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_decide_leave_request(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 19) فك الحظر + إزالة من سجل المغادرين (المالك)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_owner_unban_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
BEGIN
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_owner LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;
  DELETE FROM org_banned_users WHERE org_id = v_org AND user_id = p_user_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.org_owner_remove_alumni_row(p_alumni_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
BEGIN
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_owner LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;
  DELETE FROM org_member_alumni WHERE id = p_alumni_id AND org_id = v_org;
  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_owner_unban_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.org_owner_remove_alumni_row(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 20) تحديث org_submit_join_request (رمز 10 أرقام) للتحقق من الحظر
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_submit_join_request(
  p_recruit_code text,
  p_verification_request_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_code text := regexp_replace(trim(coalesce(p_recruit_code, '')), '\D', '', 'g');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;
  IF length(v_code) != 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_code');
  END IF;

  SELECT id INTO v_org FROM org_units WHERE recruit_join_code = v_code LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_code');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_banned_users b WHERE b.org_id = v_org AND b.user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'banned_from_org');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_memberships WHERE user_id = v_uid AND status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_member');
  END IF;

  IF EXISTS (
    SELECT 1 FROM org_join_requests j
    WHERE j.applicant_user_id = v_uid AND j.status = 'pending'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_pending');
  END IF;

  INSERT INTO org_join_requests (
    org_id,
    applicant_user_id,
    status,
    verification_request_id
  )
  VALUES (v_org, v_uid, 'pending', p_verification_request_id);

  RETURN jsonb_build_object('ok', true, 'org_id', v_org);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_submit_join_request(text, bigint) TO authenticated;

-- ---------------------------------------------------------------------------
-- 21) إزالة عضو نشط (المالك)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.org_owner_remove_member(p_member_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
BEGIN
  IF v_owner IS NULL OR p_member_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_args');
  END IF;
  IF p_member_user_id = v_owner THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cannot_remove_self');
  END IF;
  SELECT id INTO v_org FROM org_units WHERE owner_user_id = v_owner LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM org_memberships m
    WHERE m.org_id = v_org AND m.user_id = p_member_user_id AND m.member_role = 'member' AND m.status = 'active'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_member');
  END IF;

  DELETE FROM org_memberships
  WHERE org_id = v_org AND user_id = p_member_user_id AND member_role = 'member';

  UPDATE users_profiles SET org_id = NULL
  WHERE user_id = p_member_user_id AND org_id IS NOT DISTINCT FROM v_org;

  INSERT INTO org_member_alumni (org_id, user_id, note)
  VALUES (v_org, p_member_user_id, 'owner_removed');

  PERFORM public._inapp_enqueue_for_user(
    p_member_user_id,
    'org_removed',
    'تمت إزالتك من الفريق',
    'لم تعد ضمن منشأة صاحب الحساب.',
    jsonb_build_object('org_id', v_org::text)
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_owner_remove_member(uuid) TO authenticated;
