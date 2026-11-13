BEGIN;

-- إضافة أعمدة نفاذ إلى users_profiles
ALTER TABLE IF EXISTS public.users_profiles
ADD COLUMN IF NOT EXISTS nafath_verified_at timestamptz,
ADD COLUMN IF NOT EXISTS nafath_data jsonb,
ADD COLUMN IF NOT EXISTS auth_method text DEFAULT 'traditional';

-- المسح: بدل البيانات القديمة (إن وجدت) بـ JSON جديد
CREATE INDEX IF NOT EXISTS idx_users_profiles_auth_method
  ON public.users_profiles (auth_method)
  WHERE auth_method = 'nafath';

CREATE INDEX IF NOT EXISTS idx_users_profiles_nafath_verified
  ON public.users_profiles (nafath_verified_at DESC NULLS LAST)
  WHERE nafath_verified_at IS NOT NULL;

-- يجب ربط إنشاء الملف بالمستخدم المصادق عليه، وليس بمجرد وجود طلب نفاذ.
DROP POLICY IF EXISTS users_profiles_signup_rls_safe ON public.users_profiles;
CREATE POLICY users_profiles_signup_rls_safe
  ON public.users_profiles
  FOR INSERT
  WITH CHECK (
    (auth.uid() = user_id) OR
    (auth.role() = 'service_role')
  );

COMMIT;
