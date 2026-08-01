-- معاينة منشأة برمز فال (دعوة) قبل تسجيل المستخدم + توسيع JSON الصلاحيات الافتراضية

BEGIN;

CREATE OR REPLACE FUNCTION public._norm_org_invite_code(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(
    regexp_replace(
      coalesce(trim(p), ''),
      '[^A-Z0-9]',
      '',
      'g'
    )
  );
$$;

COMMENT ON FUNCTION public._norm_org_invite_code(text) IS
  'تطبيع رمز الدعوة/فال لمقارنة آمنة (أحرف وأرقام فقط، بدون شرطات).';

CREATE OR REPLACE FUNCTION public.org_preview_by_invite_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  r record;
BEGIN
  v_key := public._norm_org_invite_code(p_code);
  IF length(v_key) < 6 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_code');
  END IF;

  SELECT
    id,
    account_type,
    display_name_ar,
    display_name_en,
    logo_url,
    fal_public_code
  INTO r
  FROM public.org_units
  WHERE fal_public_code IS NOT NULL
    AND length(trim(fal_public_code)) > 0
    AND public._norm_org_invite_code(fal_public_code) = v_key
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'org_id', r.id,
    'account_type', r.account_type,
    'display_name_ar', coalesce(r.display_name_ar, ''),
    'display_name_en', coalesce(r.display_name_en, ''),
    'logo_url', coalesce(r.logo_url, ''),
    'fal_public_code', coalesce(r.fal_public_code, '')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.org_preview_by_invite_code(text) TO anon, authenticated, service_role;

-- توسيع الصلاحيات الافتراضية للأعضاء الجدد (الأعمدة JSON في org_memberships)
CREATE OR REPLACE FUNCTION public.org_default_member_permissions()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'manage_team', false,
    'add_properties', false,
    'add_ads', false,
    'add_listing_requests', false,
    'edit_properties', false,
    'view_market', false,
    'view_profile', true,
    'access_chat', true,
    'edit_org_settings', false,
    'view_analytics', false,
    'manage_subscription', false,
    'export_data', false,
    'invite_members', false,
    'manage_chat_rooms', false,
    'view_member_activity', false,
    'desk', false,
    'middle_nav', false
  );
$$;

COMMIT;
