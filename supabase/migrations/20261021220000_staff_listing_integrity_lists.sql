-- قائمة الموظفين للإعلانات المُصعّدة (بلاغات) مع بيانات مختصرة للإعلان.
BEGIN;

CREATE OR REPLACE FUNCTION public.platform_staff_list_escalations(p_limit int DEFAULT 80)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(x ORDER BY x.distinct_reporters_7d DESC, x.first_escalated_at DESC)
    FROM (
      SELECT
        e.property_id,
        e.distinct_reporters_7d,
        e.first_escalated_at,
        to_jsonb(p) ->> 'title' AS title,
        to_jsonb(p) ->> 'city' AS city,
        coalesce(p.report_staff_hidden, false) AS staff_hidden,
        coalesce(p.home_feed_suppressed, false) AS suppressed
      FROM public.listing_moderation_escalations e
      JOIN public.properties p ON p.id = e.property_id
      WHERE e.status = 'open'
      ORDER BY e.distinct_reporters_7d DESC, e.first_escalated_at DESC
      LIMIT greatest(1, least(coalesce(p_limit, 80), 200))
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_list_escalations(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_escalations(int) TO authenticated;

COMMIT;
