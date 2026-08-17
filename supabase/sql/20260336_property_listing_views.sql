-- تتبع مشاهدات الإعلان: حدث لكل مشاهدة + تجميع للمالك.
-- نفّذ في Supabase SQL Editor ثم فعّل RLS حسب بيئتك.

CREATE TABLE IF NOT EXISTS public.property_listing_view_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  viewer_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  viewer_display_name text NOT NULL DEFAULT '',
  viewer_is_marketer boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_plve_property
  ON public.property_listing_view_events (property_id);

CREATE INDEX IF NOT EXISTS idx_plve_property_created
  ON public.property_listing_view_events (property_id, created_at DESC);

ALTER TABLE public.property_listing_view_events ENABLE ROW LEVEL SECURITY;

-- الإدراج عبر الدالة SECURITY DEFINER فقط (لا سياسة insert للعميل).

DROP POLICY IF EXISTS plve_select_property_owner ON public.property_listing_view_events;
CREATE POLICY plve_select_property_owner ON public.property_listing_view_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.properties pr
      WHERE pr.id = property_id AND pr.owner_id = auth.uid()
    )
  );

-- تسجيل مشاهدة (مصادق أو زائر عبر anon إن فعّلت لاحقاً)
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
    SELECT COALESCE(NULLIF(trim(up.username::text), ''), 'مستخدم')
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

REVOKE ALL ON FUNCTION public.record_property_listing_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_property_listing_view(uuid) TO authenticated;

-- تجميع للمالك فقط
CREATE OR REPLACE FUNCTION public.property_listing_view_aggregates(p_property_id uuid)
RETURNS TABLE (
  viewer_id uuid,
  viewer_label text,
  view_count bigint,
  last_viewed_at timestamptz,
  is_marketer boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.properties pr
    WHERE pr.id = p_property_id AND pr.owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  RETURN QUERY
  SELECT
    e.viewer_id,
    COALESCE(NULLIF(trim(max(e.viewer_display_name)), ''), '—') AS viewer_label,
    count(*)::bigint AS view_count,
    max(e.created_at) AS last_viewed_at,
    bool_or(e.viewer_is_marketer) AS is_marketer
  FROM public.property_listing_view_events e
  WHERE e.property_id = p_property_id
  GROUP BY e.viewer_id
  ORDER BY view_count DESC, last_viewed_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.property_listing_view_aggregates(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_listing_view_aggregates(uuid) TO authenticated;
