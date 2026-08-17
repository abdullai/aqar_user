# تقرير إدارة الموافقات — Consent Management Report

**الجهة:** موثوق الإلكترونية — **المنتج:** المنصة العقارية الموثوقة  
**التاريخ:** 2026-05-14

---

## تأكيد القيود (إلزامي)

DOCUMENTATION ONLY — NO UI CHANGES.

---

## 1) المنفّذ في المخطط (Fact)

| العنصر | التنفيذ |
|---------|---------|
| تفضيلات الكوكيز/التتبع/التسويق | `regc_consent_preferences` (حقول: `analytics_cookies`, `marketing_cookies`, `essential_ack`) |
| تحديث عبر RPC | `upsert_consent_preferences_v1` + تدقيق `consent.preferences_updated` |
| قبول السياسات القانونية | `regc_user_legal_acceptances` + `record_legal_acceptances_after_terms_v1` |
| versioning للنصوص | `regc_legal_policy_documents` |

**المصدر:** `20260515183000_compliance_legal_audit_rls.sql`

---

## 2) نموذج الموافقة (GDPR-style alignment — تصميم)

- **Necessary / Essential:** `essential_ack` — مطلوب للتشغيل وفق المنتج.  
- **Analytics:** اختياري.  
- **Marketing:** اختياري.  
- **سحب الموافقة:** عبر نفس مسار التحديث؛ يُسجّل في التدقيق عند استدعاء RPC.

---

## 3) النصوص القانونية الكاملة

المراجع الطويلة: `docs/compliance/` (AR/EN) — **مراجعة محامٍ قبل النشر الرسمي**.

---

## 4) سياسات إضافية طلبها نموذج امتثال عام

**Refund & Subscription Policy** و**Payment Policy** و**IP Policy** كاملة: تُوجد في `docs/compliance/` بصيغ متنوعة؛ الربط الإلزامي بـ `regc_legal_policy_documents` يتوسع عند إضافة صفوف `policy_type` جديدة في ترحيل لاحق **خارج نطاق هذه الوثيقة** إن لزم.

**نهاية التقرير.**
