-- =============================================================================
-- بوابة «مراجعة بيانات» عند تحديث التطبيق: يقارن العميل kAppRequiredProfileDataRevision
-- مع users_profiles.profile_data_revision ثم يستدعي ack_profile_data_revision.
-- =============================================================================

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS profile_data_revision integer NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.users_profiles.profile_data_revision IS
  'آخر مراجعة بيانات أكدها المستخدم؛ إن كان أقل من إصدار التطبيق المطلوب يُعرض شاشة الاستكمال.';

COMMIT;
