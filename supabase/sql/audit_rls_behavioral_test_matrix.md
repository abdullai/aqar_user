# مصفوفة اختبار RLS سلوكي (يدوي / أتمتة)

تنفيذ **حقيقي** لاختبارات `anon` مقابل `authenticated` يتطلب طلبات REST أو عميل Supabase يحمل JWT المقابل. محرر SQL الافتراضي يعمل بدور **postgres** ولا يُحاكي anon.

## 1) anon — يجب أن يفشل

| العملية | الجدول | الطريقة |
|--------|--------|---------|
| INSERT | `regc_audit_logs` | REST `POST` بمفتاح anon |
| UPDATE | `regc_user_complaints` | REST PATCH |
| SELECT | `regc_audit_logs` (سجلات مستخدمين) | يفترض رفض أو صفوف فارغة حسب السياسة |

## 2) authenticated — يجب أن ينجح ضمن الملكية

| العملية | المسار |
|--------|--------|
| INSERT | `regc_user_complaints` مع `user_id` = `auth.uid()` |
| SELECT | صفوف المستخدم لـ `regc_audit_logs` عبر سياسة `user_id = auth.uid()` |
| RPC | `rpc('compliance_append_audit', …)` |

## 3) service_role

يستخدم فقط من الخادم/الأدوات الإدارية؛ **لا** تضمّن مفتاح service في تطبيق العميل. تحقق من أن CI لا يطبع المفتاح.

## 4) JWT مزور / manipulation

- اختبر REST بـ `Authorization: Bearer <invalid>` → 401.
- توكن من مشروع آخر → رفض.
- تعديل payload يدوياً بدون توقيع صحيح → رفض.

## 5) privilege escalation

- مستخدم A يحاول `UPDATE` صفاً `user_id` = B على `regc_user_complaints` → يجب 0 rows affected أو خطأ RLS.

سجّل النتائج في `docs/security/SECURITY_AUDIT_REPORT.md` (قسم نتائج الاختبار).

