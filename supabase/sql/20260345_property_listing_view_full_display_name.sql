-- تسجيل مشاهدة الإعلان باسم ظاهر من الملف الشخصي بدل الاعتماد على username فقط (غالباً رقم هوية).
CREATE OR REPLACE FUNCTION public.record_property_listing_view(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_name text := '';
  v_mkt boolean := false;
BEGIN
  IF p_property_id IS NULL THEN
    RETURN;
  END IF;

  IF uid IS NOT NULL THEN
    SELECT COALESCE(
      NULLIF(trim(up.full_name_ar::text), ''),
      NULLIF(trim(up.full_name_en::text), ''),
      NULLIF(trim(
        concat_ws(' ', NULLIF(trim(up.first_name_ar::text), ''), NULLIF(trim(up.fourth_name_ar::text), ''))
      ), ''),
      NULLIF(trim(
        concat_ws(' ', NULLIF(trim(up.first_name_en::text), ''), NULLIF(trim(up.fourth_name_en::text), ''))
      ), ''),
      NULLIF(trim(up.full_name::text), ''),
      NULLIF(trim(up.username::text), ''),
      'مستخدم'
    )
    INTO v_name
    FROM public.users_profiles up
    WHERE up.user_id = uid
    LIMIT 1;

    IF v_name IS NULL OR trim(v_name) = '' THEN
      v_name := 'مستخدم';
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.marketer_profiles mp WHERE mp.user_id = uid
    ) INTO v_mkt;
  ELSE
    v_name := 'زائر';
  END IF;

  INSERT INTO public.property_listing_view_events (
    property_id, viewer_id, viewer_display_name, viewer_is_marketer
  ) VALUES (
    p_property_id, uid, COALESCE(v_name, 'زائر'), COALESCE(v_mkt, false)
  );

  UPDATE public.properties
  SET views = COALESCE(views, 0) + 1
  WHERE id = p_property_id;
END;
$$;
