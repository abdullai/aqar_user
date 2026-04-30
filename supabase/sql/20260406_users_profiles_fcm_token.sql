-- =============================================================================
-- users_profiles: مرآة اختيارية لـ fcm_token (إلى جانب user_push_tokens)
-- التطبيق يحدّث العمودين معاً عبر Supabase client بعد تسجيل الدخول.
-- =============================================================================

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fcm_token text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fcm_token_updated_at timestamptz;

COMMENT ON COLUMN public.users_profiles.fcm_token IS
  'آخر FCM token للمستخدم (مرآة؛ المصدر الرسمي للإرسال: user_push_tokens).';

COMMENT ON COLUMN public.users_profiles.fcm_token_updated_at IS
  'وقت آخر تحديث لـ fcm_token من العميل.';

COMMIT;

-- بعد تطبيق هذا الملف، طبّق 20260407_sync_user_fcm_profile_token_rpc.sql
-- ثم يستدعي التطبيق RPC: sync_user_fcm_profile_token(p_fcm_token => ...).

-- =============================================================================
-- تفعيل Webhooks في لوحة Supabase (Database → Webhooks):
-- 1) جدول public.messages — حدث INSERT — POST إلى
--    https://<PROJECT_REF>.supabase.co/functions/v1/send_push
--    Header: Authorization: Bearer <SERVICE_ROLE_KEY>
--    Body: قالب Supabase الافتراضي (يتضمن type, table, record).
-- 2) جدول public.reservations — حدث INSERT — نفس الرابط.
-- =============================================================================
