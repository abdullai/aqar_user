# مراجعة أداء Supabase (فهارس + RLS + حجم بيانات)

هذا المسار يكمّل تحسينات العميل (Flutter) ولا يغني عن قياس زمن الاستعلام على الخادم.

## 1) تشغيل حزمة الجرد (مرة واحدة)

في **Supabase → SQL Editor** شغّل الملف:

- [`sql/diagnostics_supabase_performance_audit_bundle.sql`](sql/diagnostics_supabase_performance_audit_bundle.sql)

صدّر النتائج للأقسام 1–5 (جدول/CSV) وأرسلها للمراجعة.

## 2) تشخيص وظيفي إضافي (اختياري، من المستودع)

- [`sql/diagnostics_home_feed_data_quality.sql`](sql/diagnostics_home_feed_data_quality.sql) — توافق بيانات الرئيسية مع RLS والسياسات.
- [`sql/diagnostics_guest_public_listings_visibility.sql`](sql/diagnostics_guest_public_listings_visibility.sql) — إن اختبرت وضع الضيف.

## 3) تثبيت الاستعلام البطيء (EXPLAIN)

- [`sql/diagnostics_performance_explain_template.sql`](sql/diagnostics_performance_explain_template.sql) — انسخ الاستعلام الحقيقي من السجلات، ثم شغّل `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`.

## 4) بعد استلام النتائج

1. مطابقة `seq_scan` العالي و`idx_scan` المنخفض مع استعلامات التطبيق.
2. مراجعة نصوص `pg_policies` (تجنّب subquery ثقيل لكل صف إن أمكن).
3. اقتراح فهارس محددة — القوالب المعطّلة في [`sql/diagnostics_suggested_indexes_TEMPLATE.sql`](sql/diagnostics_suggested_indexes_TEMPLATE.sql) للمرجعية فقط؛ **لا تُلغى التعليق** قبل `EXPLAIN` ومراجعة يدوية.

## 5) ملاحظات تنفيذ

- في الإنتاج يُفضّل `CREATE INDEX CONCURRENTLY` وخارج الذروة.
- نفّذ `ANALYZE` على الجداول المتأثرة بعد إنشاء فهارس كبيرة.
- لا تحذف فهارساً (`DROP INDEX`) دون التأكد أنها ليست جزءاً من قيد UNIQUE أو FK.
