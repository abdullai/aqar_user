-- =============================================================================
-- Patch إن نفّذت 20260422_users_profiles_rls_consolidated_fix.sql وما زال GET users_profiles = 500
--
-- السبب الشائع: داخل app_rls_users_profile_select_allowed يُقرأ properties (أو غيره)
-- وسياسات تلك الجداول تعيد النظر في users_profiles → حلقة أو خطأ داخلي.
--
-- الحل: تشغيل الدالة المساعدة مع row_security = off لمدة استدعائها فقط (آمن نسبياً
-- لأنها ترجع boolean ولا تُرجع صفوفاً؛ القراءة الفعلية للملفات ما زالت عبر سياسة SELECT).
--
-- نفّذ مرة واحدة في Supabase → SQL Editor.
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

COMMIT;
