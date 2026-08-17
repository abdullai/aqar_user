-- =============================================================================
-- تشخيص قبل/بعد ترحيل الامتثال (20260515183000)
-- ملاحظة: صف security_events بـ has_user_id = false متوقع إن وُجد جدول قديم عام؛
-- الترحيل يستخدم regc_security_events ولا يلمس security_events.
-- انسخ النتائج من محرر SQL في Supabase إن استمر خطأ غير 42703.
-- =============================================================================

-- 1) أي جدول من الأسماء المتوقعة موجود، وأعمدته؟
SELECT
  c.table_name,
  c.column_name,
  c.data_type,
  c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN (
    'legal_policy_documents',
    'user_legal_acceptances',
    'compliance_audit_logs',
    'compliance_incidents',
    'compliance_user_complaints',
    'compliance_complaint_escalations',
    'security_events',
    'consent_preferences',
    'complaints',
    -- أسماء الترحيل بعد إعادة التسمية (regc_*)
    'regc_legal_policy_documents',
    'regc_user_legal_acceptances',
    'regc_audit_logs',
    'regc_incidents',
    'regc_user_complaints',
    'regc_complaint_escalations',
    'regc_security_events',
    'regc_consent_preferences'
  )
ORDER BY c.table_name, c.ordinal_position;

-- 2) جداول public التي اسمها يحتوي audit / complaint / consent / security (للعثور على تعارضات)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND (
    table_name ILIKE '%audit%'
    OR table_name ILIKE '%complaint%'
    OR table_name ILIKE '%consent%'
    OR table_name ILIKE '%security_event%'
    OR table_name = 'complaints'
  )
ORDER BY table_name;

-- 3) هل يوجد عمود user_id في الجداول المشتبه بها؟ (ملخص)
-- يشمل أسماء الترحيل regc_* بعد إصلاح التعارض مع جداول عامة مثل security_events.
SELECT
  t.table_name,
  bool_or(c.column_name = 'user_id') AS has_user_id
FROM information_schema.tables t
LEFT JOIN information_schema.columns c
  ON c.table_schema = t.table_schema
 AND c.table_name = t.table_name
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
  AND t.table_name IN (
    'compliance_audit_logs',
    'security_events',
    'consent_preferences',
    'compliance_user_complaints',
    'complaints',
    'regc_audit_logs',
    'regc_security_events',
    'regc_consent_preferences',
    'regc_user_complaints'
  )
GROUP BY t.table_name
ORDER BY t.table_name;
