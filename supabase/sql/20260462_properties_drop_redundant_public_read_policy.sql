-- =============================================================================
-- إصلاح تداخل سياسات SELECT على public.properties
--
-- المشكلة المحتملة (PostgreSQL RLS):
--   عند وجود سياسة RESTRICTIVE مع سياسات PERMISSIVE، يجب أن تمرّ **كل**
--   سياسات RESTRICTIVE للصف + سياسة PERMISSIVE واحدة على الأقل.
--   سياسة قديمة مثل `properties_public_read_published_like` تقتصر على:
--     status IN ('active','available','published')
--   فتفشل لكل المسودات (draft) حتى لو `properties_public_home_select` تسمح
--   بـ draft + waiting_marketers / … — فيختفي الإعلان من PostgREST للضيف.
--
-- الحل: إزالة السياسة الضيّقة لأن `properties_public_home_select` (20260461)
-- يغطي بالفعل الحالات المنشورة (active/available/published ضمن القائمة الأوسع)
-- ومسار المسودة الحيّ، مع احترام home_feed_suppressed.
--
-- نفّذ في Supabase → SQL Editor بعد مراجعة أن لا يعتمد عليها منطق آخر.
-- =============================================================================

DROP POLICY IF EXISTS "properties_public_read_published_like" ON public.properties;
