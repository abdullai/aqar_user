-- =============================================================================
-- RLS: المسوّق يقرأ اسم/بيانات المالك فقط عند وجود دعوة listing_request_invites
-- تربط marketer_id الحالي بـ request_id، والمالك هو listing_requests.owner_id.
--
-- يصلح خطأ 42703 إن كان جدول profiles بدون عمود user_id (الربط عبر profiles.id = owner_id).
--
-- نفّذ في Supabase SQL Editor. يستبدل السياسات العريضة السابقة إن وُجدت.
-- =============================================================================

BEGIN;

-- إزالة نسخة سابقة (أي طلب إدراج للمالك — عريضة جداً)
DROP POLICY IF EXISTS "Marketers read listing request owners users_profiles"
  ON public.users_profiles;

DROP POLICY IF EXISTS "Marketers read listing request owners profiles"
  ON public.profiles;

-- ---------------------------------------------------------------------------
-- users_profiles: صف المالك فقط إذا كانت للمسوّق دعوة على ذلك الطلب
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Marketers read invite-linked owner users_profiles"
  ON public.users_profiles;

CREATE POLICY "Marketers read invite-linked owner users_profiles"
  ON public.users_profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.listing_request_invites inv
      JOIN public.listing_requests lr ON lr.id = inv.request_id
      WHERE inv.marketer_id = auth.uid()
        AND lr.owner_id = users_profiles.user_id
        AND coalesce(lower(trim(inv.status::text)), '') NOT IN (
          'declined',
          'expired',
          'cancelled',
          'revoked'
        )
        AND lower(coalesce(nullif(trim(lr.workflow_stage), ''), '')) NOT IN (
          'cancelled',
          'terminated',
          'rejected',
          'owner_withdrawn',
          'deleted'
        )
    )
  );

-- ---------------------------------------------------------------------------
-- profiles: نفس المنطق — المفتاح هو id (يساوي auth.users / owner_id)
-- لا يُستخدم profiles.user_id (قد لا يوجد في مخططك).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Marketers read invite-linked owner profiles"
  ON public.profiles;

CREATE POLICY "Marketers read invite-linked owner profiles"
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.listing_request_invites inv
      JOIN public.listing_requests lr ON lr.id = inv.request_id
      WHERE inv.marketer_id = auth.uid()
        AND lr.owner_id = profiles.id
        AND coalesce(lower(trim(inv.status::text)), '') NOT IN (
          'declined',
          'expired',
          'cancelled',
          'revoked'
        )
        AND lower(coalesce(nullif(trim(lr.workflow_stage), ''), '')) NOT IN (
          'cancelled',
          'terminated',
          'rejected',
          'owner_withdrawn',
          'deleted'
        )
    )
  );

COMMIT;
