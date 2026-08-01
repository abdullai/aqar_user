-- باقات منفصلة: individual | marketer | office | institution | company (3 مستويات لكل نوع).
-- المسوّق: max_members = 0 (عمل فردي) — إضافة عضو عبر مقاعد إضافية مدفوعة.

UPDATE public.subscription_plans SET is_active = false WHERE is_active = true;

INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active
)
SELECT * FROM (VALUES
  -- معلن / مستخدم فردي
  (N'أساسي', 'Basic', 'individual', 49::numeric, 470.40::numeric, 1, NULL::int, 40::int, 15::int, true, false, false, false, 1, true),
  (N'احترافي', 'Professional', 'individual', 119::numeric, 1142.40::numeric, 1, NULL::int, 250::int, 100::int, true, true, false, false, 2, true),
  (N'مميز', 'Enterprise', 'individual', 349::numeric, 3350.40::numeric, 1, NULL::int, NULL::int, NULL::int, true, true, true, true, 3, true),
  -- مسوّق عقاري فردي (بدون مقاعد فريق ضمن الباقة)
  (N'أساسي', 'Basic', 'marketer', 89::numeric, 854.40::numeric, 0, NULL::int, 60::int, 25::int, true, false, false, false, 1, true),
  (N'احترافي', 'Professional', 'marketer', 199::numeric, 1910.40::numeric, 0, NULL::int, 450::int, 180::int, true, true, false, true, 2, true),
  (N'مميز', 'Enterprise', 'marketer', 449::numeric, 4310.40::numeric, 0, NULL::int, NULL::int, NULL::int, true, true, true, true, 3, true),
  -- مكتب عقاري (3 مقاعد)
  (N'أساسي', 'Basic', 'office', 129::numeric, 1238.40::numeric, 3, NULL::int, 80::int, 35::int, true, false, false, false, 1, true),
  (N'احترافي', 'Professional', 'office', 279::numeric, 2678.40::numeric, 3, NULL::int, 600::int, 250::int, true, true, false, true, 2, true),
  (N'مميز', 'Enterprise', 'office', 649::numeric, 6230.40::numeric, 3, NULL::int, NULL::int, NULL::int, true, true, true, true, 3, true),
  -- مؤسسة (6 مقاعد)
  (N'أساسي', 'Basic', 'institution', 179::numeric, 1718.40::numeric, 6, NULL::int, 120::int, 50::int, true, false, false, false, 1, true),
  (N'احترافي', 'Professional', 'institution', 379::numeric, 3638.40::numeric, 6, NULL::int, 900::int, 400::int, true, true, false, true, 2, true),
  (N'مميز', 'Enterprise', 'institution', 849::numeric, 8150.40::numeric, 6, NULL::int, NULL::int, NULL::int, true, true, true, true, 3, true),
  -- شركة (9 مقاعد)
  (N'أساسي', 'Basic', 'company', 229::numeric, 2198.40::numeric, 9, NULL::int, 150::int, 65::int, true, false, false, false, 1, true),
  (N'احترافي', 'Professional', 'company', 479::numeric, 4598.40::numeric, 9, NULL::int, 1200::int, 500::int, true, true, false, true, 2, true),
  (N'مميز', 'Enterprise', 'company', 999::numeric, 9590.40::numeric, 9, NULL::int, NULL::int, NULL::int, true, true, true, true, 3, true)
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
  WHERE sp.user_type = v.user_type
    AND sp.name_en = v.name_en
    AND sp.is_active = true
);

-- مسوّق فردي: وحدة منشأة بمقعد واحد (المالك) + مقاعد إضافية مدفوعة
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
  FROM public.users_profiles
  WHERE user_id = v_uid;

  IF v_type IS NULL OR v_type NOT IN ('office', 'institution', 'company', 'marketer') THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NOT NULL THEN
    v_limit := CASE v_type
      WHEN 'marketer' THEN 1
      WHEN 'office' THEN 3
      WHEN 'institution' THEN 6
      WHEN 'company' THEN 9
      ELSE 1
    END;
    UPDATE public.org_units
    SET
      account_type = CASE WHEN v_type = 'marketer' THEN 'office' ELSE v_type END,
      base_seat_limit = v_limit,
      updated_at = now()
    WHERE id = v_org
      AND (base_seat_limit IS DISTINCT FROM v_limit);
    UPDATE public.users_profiles SET org_id = v_org WHERE user_id = v_uid AND (org_id IS DISTINCT FROM v_org);
    RETURN v_org;
  END IF;

  v_limit := CASE v_type
    WHEN 'marketer' THEN 1
    WHEN 'office' THEN 3
    WHEN 'institution' THEN 6
    WHEN 'company' THEN 9
    ELSE 1
  END;

  INSERT INTO public.org_units (owner_user_id, account_type, base_seat_limit)
  VALUES (
    v_uid,
    CASE WHEN v_type = 'marketer' THEN 'office' ELSE v_type END,
    v_limit
  )
  RETURNING id INTO v_org;

  INSERT INTO public.org_memberships (org_id, user_id, member_role, permissions, status)
  VALUES (
    v_org,
    v_uid,
    'owner',
    '{"manage_team": true, "add_properties": true, "add_ads": true, "view_market": true, "view_profile": true, "access_chat": true, "edit_org_settings": true, "view_analytics": true, "desk": true, "middle_nav": true}'::jsonb,
    'active'
  );

  UPDATE public.users_profiles SET org_id = v_org WHERE user_id = v_uid;

  RETURN v_org;
END;
$$;
