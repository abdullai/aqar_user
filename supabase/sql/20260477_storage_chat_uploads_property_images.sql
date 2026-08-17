-- =============================================================================
-- 20260477 — مرفقات الدردشة والـ Storage (مرجع)
-- ═══════════════════════════════════════════════════════════════════════════
-- 1) ما يفعله التطبيق الآن (بدون سياسات جديدة)
-- ═══════════════════════════════════════════════════════════════════════════
-- رفع الصور في الدردشة يستخدم المسار:
--   property-images/market-requests/{user_id}/chat/{conversation_id}/{uuid}.jpg
-- وهو مغطى بسياسات bucket «market-requests/{uid}/%» في:
--   supabase/sql/20260472_storage_market_request_covers.sql
-- إن وُجدت تلك السياسات على مشروعك، ينجح الرفع من التطبيق دون إنشاء chat_uploads_*.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- 2) إن أردت مجلداً مستقلاً chat-uploads/{uid}/...
-- ═══════════════════════════════════════════════════════════════════════════
-- على Supabase Cloud لا يعمل CREATE POLICY من SQL Editor (قيود المالك).
-- الخيارات:
--   • Dashboard → Storage → property-images → Policies (انظر التعبيرات أسفل).
--   • أو من الجهاز: supabase link && supabase db push
--     باستخدام: supabase/migrations/20260417140000_storage_chat_uploads_policies.sql
--
-- ═══════════════════════════════════════════════════════════════════════════
-- تعبيرات السياسات (للمجلد chat-uploads فقط — إن طبّقتها يدوياً أو عبر db push)
-- ═══════════════════════════════════════════════════════════════════════════
-- INSERT — WITH CHECK:
-- (bucket_id = 'property-images'
--   AND auth.role() = 'authenticated'
--   AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%'))
--
-- UPDATE — USING و WITH CHECK (نفس التعبير):
-- (bucket_id = 'property-images'
--   AND auth.role() = 'authenticated'
--   AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%'))
--
-- DELETE — USING:
-- (bucket_id = 'property-images'
--   AND auth.role() = 'authenticated'
--   AND name ~~ ('chat-uploads/' || (auth.uid())::text || '/%'))
-- =============================================================================

SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND (
    policyname LIKE 'chat_uploads%'
    OR policyname LIKE '%market_request_covers%'
  )
ORDER BY policyname;
