-- =============================================================================
-- إصلاح 401 على property_images (نسخة v4)
--
-- الترتيب الإلزامي:
--   1) APPLY_NOW_00_is_admin_grant_anon.sql
--   2) هذا الملف (بدون SET ROLE anon — لا يُظهر خطأ وهمياً)
--
-- ما يفعله v4:
--   • يزيل كل سياسات SELECT على property_images ثم يعيد الثلاث الأساسية
--   • لا EXISTS مباشر على properties داخل USING (تجنّب is_admin عبر RLS)
--   • دوال SECURITY DEFINER + row_security = off
-- =============================================================================

BEGIN;

-- ── 0) is_admin — إن وُجدت الدالة (تكرار آمن إن نفّذت 00 مسبقاً) ──
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_admin'
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', r.fn);
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;

ALTER TABLE public.property_images ENABLE ROW LEVEL SECURITY;

-- ── 1) دوال مساعدة (بدون تقييم RLS على properties) ──

CREATE OR REPLACE FUNCTION public.property_id_public_home_feed_visible(
  p_property_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('row_security', 'off', true);
  RETURN p_property_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = p_property_id
        AND p.status IS DISTINCT FROM 'deleted'
        AND COALESCE(p.home_feed_suppressed, false) = false
        AND (
          p.status IN (
            'published', 'active', 'available', 'live', 'reserved', 'approved',
            'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
          )
          OR (
            p.status = 'draft'
            AND p.workflow_stage IN (
              'waiting_marketers', 'marketer_selected', 'contract_pending',
              'contract_sent', 'contract_returned', 'contract_signed',
              'permit_pending', 'permit_issued', 'published', 'reserved', 'inactive_72h'
            )
          )
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.property_image_owned_by_auth_user(
  p_property_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('row_security', 'off', true);
  RETURN auth.uid() IS NOT NULL
    AND p_property_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = p_property_id
        AND p.owner_id = auth.uid()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.property_id_public_home_feed_visible(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_id_public_home_feed_visible(uuid)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.property_image_owned_by_auth_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_image_owned_by_auth_user(uuid)
  TO authenticated, service_role;

ALTER FUNCTION public.property_id_public_home_feed_visible(uuid) OWNER TO postgres;
ALTER FUNCTION public.property_image_owned_by_auth_user(uuid) OWNER TO postgres;

-- ── 2) إزالة كل سياسات SELECT القديمة (تجنّب بقاء سياسة فيها is_admin) ──

DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'property_images'
      AND cmd IN ('SELECT', 'ALL')
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.property_images',
      pol.policyname
    );
    RAISE NOTICE 'Dropped policy %', pol.policyname;
  END LOOP;
END $$;

-- ── 3) سياسات جديدة فقط (OR بينها — بدون EXISTS على properties في النص) ──

CREATE POLICY "property_images_anon_home_embed"
  ON public.property_images
  FOR SELECT
  TO anon, authenticated
  USING (public.property_id_public_home_feed_visible(property_id));

CREATE POLICY "owner_select_images_of_own_properties"
  ON public.property_images
  FOR SELECT
  TO authenticated
  USING (public.property_image_owned_by_auth_user(property_id));

DO $$
BEGIN
  IF to_regprocedure('public.marketer_can_read_property_for_marketing(uuid)') IS NOT NULL THEN
    EXECUTE $pol$
      CREATE POLICY "marketer_select_linked_property_images_v2"
        ON public.property_images
        FOR SELECT
        TO authenticated
        USING (public.marketer_can_read_property_for_marketing(property_id))
    $pol$;
  ELSE
    RAISE NOTICE 'marketer_can_read_property_for_marketing missing — skipped marketer image policy';
  END IF;
END $$;

COMMIT;

-- ─── تحقق كمشرف فقط (لا SET ROLE — اختبر REST من المتصفح) ───
SELECT policyname, roles::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'property_images'
  AND cmd = 'SELECT'
ORDER BY policyname;

SELECT count(*)::bigint AS total_property_images FROM public.property_images;

SELECT count(*)::bigint AS images_home_feed_visible
FROM public.property_images pi
WHERE public.property_id_public_home_feed_visible(pi.property_id);

-- REST (بعد v4):
-- GET /rest/v1/property_images?select=property_id,path&limit=1
-- Header: apikey: <sb_publishable_...>  → يجب 200 (قد يكون [])
