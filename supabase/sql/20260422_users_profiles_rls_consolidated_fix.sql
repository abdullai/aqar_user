-- =============================================================================
-- إصلاح موحّد: 42P17 infinite recursion على public.users_profiles + استعادة القراءة
--
-- السبب: سياسة RLS على users_profiles تستدعي (مباشرة أو عبر دالة غير آمنة)
-- استعلاماً يعيد تقييم RLS على نفس الجدول → حلقة لا نهائية → 500 على كل
-- GET /users_profiles (لا أسماء، لا صلاحيات في الإعدادات، أزرار تختفي).
--
-- الحل: سياسة SELECT واحدة تستدعي دالة SECURITY DEFINER تفحص الجداول الأخرى
-- فقط (properties, listing_*, org_memberships, listing_contracts) دون SELECT متداخل
-- على users_profiles داخل تعبير السياسة نفسه.
--
-- مهم: SET row_security = off على الدالة يعطّل RLS داخل جسم الدالة فقط أثناء التنفيذ
-- حتى لا تعيد سياسات properties/listing_* استعلام users_profiles → 42P17/500 يبقى.
--
-- نفّذ في Supabase → SQL Editor (مرة واحدة). يُفضّل قبلها:
--   supabase/sql/20260420_in_app_notifications_drop_duplicate_select_policy.sql
--
-- متطلبات: الجداول public.properties و public.listing_requests و
-- public.listing_request_invites. إن وُجدت فرق العمل: public.org_memberships.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.app_rls_users_profile_select_allowed(p_target uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF p_target IS NULL OR uid IS NULL THEN
    RETURN false;
  END IF;

  IF uid = p_target THEN
    RETURN true;
  END IF;

  -- طرفان في عقد تسويق (محادثة العقد، أسماء الطرفين)
  IF to_regclass('public.listing_contracts') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.listing_contracts c
      WHERE (c.owner_id = p_target OR c.marketer_id = p_target)
        AND (c.owner_id = uid OR c.marketer_id = uid)
    ) THEN
      RETURN true;
    END IF;
  END IF;

  -- أعضاء نفس المؤسسة (إدارة الفريق)
  IF to_regclass('public.org_memberships') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.org_memberships me
      INNER JOIN public.org_memberships them ON them.org_id = me.org_id
      WHERE me.user_id = uid
        AND me.status = 'active'
        AND them.user_id = p_target
        AND them.status = 'active'
    ) THEN
      RETURN true;
    END IF;
  END IF;

  -- مسوّق مدعو على طلب يملكه المالك المستهدف
  IF to_regclass('public.listing_request_invites') IS NOT NULL
     AND to_regclass('public.listing_requests') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.listing_request_invites inv
      JOIN public.listing_requests lr ON lr.id = inv.request_id
      WHERE inv.marketer_id = uid
        AND lr.owner_id = p_target
        AND coalesce(lower(trim(inv.status::text)), '') NOT IN (
          'declined',
          'expired',
          'cancelled',
          'revoked'
        )
        AND lower(coalesce(nullif(trim(lr.workflow_stage::text), ''), '')) NOT IN (
          'cancelled',
          'terminated',
          'rejected',
          'owner_withdrawn',
          'deleted'
        )
    ) THEN
      RETURN true;
    END IF;
  END IF;

  -- معلن له إعلان مرئي للجمهور (الرئيسية — أسماء المعلنين)
  IF to_regclass('public.properties') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.properties pr
      WHERE pr.owner_id = p_target
        AND lower(trim(coalesce(pr.status::text, ''))) IN (
          'published',
          'active',
          'available',
          'live',
          'reserved',
          'approved'
        )
    ) THEN
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.app_rls_users_profile_select_allowed(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_rls_users_profile_select_allowed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.app_rls_users_profile_select_allowed(uuid) TO service_role;

-- إزالة كل سياسات users_profiles ثم إعادة بناء أساسية غير متكررة
DO $$
DECLARE
  pol text;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users_profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users_profiles', pol);
  END LOOP;
END $$;

ALTER TABLE public.users_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_profiles_authenticated_select
  ON public.users_profiles
  FOR SELECT
  TO authenticated
  USING (public.app_rls_users_profile_select_allowed(user_id));

CREATE POLICY users_profiles_authenticated_insert_own
  ON public.users_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY users_profiles_authenticated_update_own
  ON public.users_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

COMMIT;

-- =============================================================================
-- بعد التنفيذ: حدّث الصفحة — يفترض أن تختفي 500 على users_profiles وتعود الأسماء.
--
-- ملاحظات أخرى من سجلات المتصفح (لا تُصلحها هذه السياسة وحدها):
-- • reserve_property → 404: نفّذ supabase/sql/20260332_reservations_cart_flow_rpcs_v1.sql
-- • contract_offer_mismatch: انظر 20260422_listing_contract_offer_repair.sql (اختياري)
-- • service worker / Cache 206: ابنِ الويب بـ flutter build web --pwa-strategy=none
-- • auth/v1/token 400: بيانات دخول أو إعدادات Auth في لوحة Supabase
-- =============================================================================
