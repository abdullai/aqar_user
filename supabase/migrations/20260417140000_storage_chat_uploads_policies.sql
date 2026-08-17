-- سياسات اختيارية لمسار chat-uploads/ (إن أردت فصل مرفقات الدردشة عن market-requests).
-- على Supabase Cloud قد لا ينجح التنفيذ من SQL Editor — استخدم:
--   supabase link --project-ref <YOUR_PROJECT_REF>
--   supabase db push
-- أو أنشئ السياسات من Dashboard (انظر supabase/sql/20260477_storage_chat_uploads_property_images.sql).
--
-- التطبيق (chat_page.dart) يستخدم افتراضياً: market-requests/{uid}/chat/... المغطى بـ 20260472.

BEGIN;

DROP POLICY IF EXISTS "chat_uploads_insert_own" ON storage.objects;
CREATE POLICY "chat_uploads_insert_own"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "chat_uploads_update_own" ON storage.objects;
CREATE POLICY "chat_uploads_update_own"
ON storage.objects
FOR UPDATE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%')
)
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "chat_uploads_delete_own" ON storage.objects;
CREATE POLICY "chat_uploads_delete_own"
ON storage.objects
FOR DELETE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%')
);

COMMIT;
