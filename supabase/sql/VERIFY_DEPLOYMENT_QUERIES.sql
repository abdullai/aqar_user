-- =============================================================================
-- استعلامات تحقق سريعة (نفّذ في SQL Editor كمسؤول / بصلاحيات كافية)
-- لا تغيّر بيانات المستخدمين؛ للقراءة والتحقق من وجود الدوال والجداول.
-- =============================================================================

-- 1) دوال الجلسة + تحليل السوق
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'register_single_user_session',
    'reconcile_user_session',
    'is_user_session_active',
    'bump_user_session_epoch',
    'get_market_insights_snapshot'
  )
ORDER BY p.proname;

-- 2) جداول الجلسات (من migrations 20260334 / 20260335)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('user_sessions', 'login_logs', 'user_session_state', 'user_login_audit')
ORDER BY table_name;

-- 3) هيكل مختصر لـ user_sessions
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'user_sessions'
ORDER BY ordinal_position;

-- 4) اختبار لقطة السوق (بدون JWT: قد يرجع null أو خطأ حسب RLS؛ الأفضل من التطبيق كمستخدم)
-- SELECT public.get_market_insights_snapshot();

-- =============================================================================
-- ملاحظات تشغيل
-- =============================================================================
-- • إن لم تظهر الدوال: نفّذ بالترتيب ملفات SQL في المستودع (مثلاً 20260408 للسوق، 20260410 لجلسة user_sessions المبسّطة).
-- • جدول user_sessions المبسّط: الدوال register_single_user_session(text) و reconcile_user_session(text) بارامتر واحد p_device (JSON).
-- • Realtime لـ user_session_state: من لوحة Supabase → Database → Replication.
-- • التطبيق يستدعي register_single_user_session بعد signedIn و reconcile_user_session عند العودة للواجهة.
