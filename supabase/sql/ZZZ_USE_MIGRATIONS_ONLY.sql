-- لا تُنفَّذ ملفات هذا المجلد يدوياً بعد 28 آب 2026.
-- مصدر الحقيقة: supabase/migrations (آخرها 20260828040000_trust_line_stability_lock.sql).
-- تطبيق SQL خارج الترتيب يكسر get_chat_list2 / RLS / الفوترة.

SELECT 'use_supabase_migrations_only'::text AS notice;
