-- نوع عمود messages.id (تشغيل في SQL Editor)
-- الدوال في المشروع تفترض uuid. إن ظهر bigint عدّل تواقيع RPC والعميل accordingly.
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'messages'
  AND column_name = 'id';
