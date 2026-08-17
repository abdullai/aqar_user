-- =============================================================================
-- صور الملف الشخصي: أعمدة (إن لم تكن موجودة) + سياسات Storage لمسار user-avatars/
-- نفّذ في Supabase SQL Editor. لا يحذف ولا يعدّل السياسات القديمة لصور العقارات.
-- =============================================================================

-- 1) أعمدة اختيارية في users_profiles (آمنة مع IF NOT EXISTS)
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS avatar_url text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS avatar_updated_at timestamptz;

COMMENT ON COLUMN public.users_profiles.avatar_url IS 'Public URL for profile photo (property-images bucket, path user-avatars/{user_id}/...)';
COMMENT ON COLUMN public.users_profiles.avatar_updated_at IS 'Last time avatar was changed';

-- 2) سياسات storage.objects — مسار: property-images/user-avatars/{auth.uid()}/...
--    (السياسات الحالية تسمح بـ {uid}/% فقط؛ هذا يكمّلها دون كسرها)
--    DROP + CREATE: إعادة التنفيذ آمنة إن وُجدت السياسات مسبقًا (خطأ 42710).

DROP POLICY IF EXISTS "owner upload own user avatars" ON storage.objects;
CREATE POLICY "owner upload own user avatars"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('user-avatars/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "owner update own user avatars" ON storage.objects;
CREATE POLICY "owner update own user avatars"
ON storage.objects
FOR UPDATE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('user-avatars/' || (auth.uid())::text || '/%')
)
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('user-avatars/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "owner delete own user avatars" ON storage.objects;
CREATE POLICY "owner delete own user avatars"
ON storage.objects
FOR DELETE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('user-avatars/' || (auth.uid())::text || '/%')
);

-- القراءة: لديك بالفعل "public read property images" على property-images — لا حاجة لسياسة SELECT إضافية.
