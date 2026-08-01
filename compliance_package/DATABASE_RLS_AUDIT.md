# تدقيق RLS وقاعدة البيانات — Database RLS Audit

**الجهة:** موثوق الإلكترونية — **المنتج:** المنصة العقارية الموثوقة  
**التاريخ:** 2026-05-14

---

## تأكيد القيود (إلزامي)

وثيقة read-only؛ لا تعديل مخطط.

---

## 1) جداول طبقة الامتثال `regc_*` (المنفّذ فعلياً)

| الجدول | RLS | ملاحظة |
|--------|-----|--------|
| `regc_legal_policy_documents` | مفعّل | قراءة `anon` للنسخ النشطة فقط (سياسة + منح SELECT) |
| `regc_user_legal_acceptances` | مفعّل | ملكية المستخدم |
| `regc_audit_logs` | مفعّل | إدخال عبر RPC فقط؛ لا INSERT مباشر لـ `authenticated` |
| `regc_incidents` | مفعّل | — |
| `regc_user_complaints` | مفعّل | شكاوى داخل التطبيق |
| `regc_complaint_escalations` | مفعّل | مرتبط بالشكوى المملوكة للمستخدم |
| `regc_security_events` | مفعّل | إدخال عبر RPC |
| `regc_consent_preferences` | مفعّل | تفضيلات الموافقة |

**المصدر:** `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`

---

## 2) إغلاق سطح `anon` (المنفّذ)

**المصدر:** `supabase/migrations/20260516100000_compliance_revoke_anon_public_surface.sql`  
**التحقق:** `validate_jwt_claims.sql`, `validate_audit_logs.sql` — PASS.

---

## 3) دوال RPC الامتثالية (ملخص)

- `compliance_append_audit(text, jsonb)`  
- `append_security_event_v1(text, jsonb)`  
- `upsert_consent_preferences_v1(boolean, boolean, boolean)`  
- `record_legal_acceptances_after_terms_v1(text, text, text)`

**منع التنفيذ لـ `anon`** بعد الترحيل الثاني (كتالوج).

---

## 4) جداول غير موجودة تحت بادئة `regc_` (وضوح تنظيمي)

الجداول التالية **وردت في بعض نماذج الامتثال العامة** لكنها **ليست** ضمن ترحيل `regc_*` الحالي في المستودع:

- `regc_subscription_transactions`  
- `regc_payment_refunds`

**الواقع المنفّذ:** الاشتراكات والمدفوعات مُعرَّفة في مسارات أخرى (مثلاً `user_subscriptions`, `billing_transactions` في `20260503120000_subscriptions_payments_billing.sql`) — راجع `PAYMENT_COMPLIANCE_REPORT.md`.

---

## 5) أدوات التحقق

`supabase/sql/staging_validation/validate_rls.sql` — `audit_rls_regc_privileges_and_policies.sql`

**نهاية التقرير.**
