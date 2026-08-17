# تقرير امتثال قاعدة البيانات — Database Compliance Report

**النطاق:** مراجعة المستودع (ترحيلات `supabase/migrations/` + دوال Edge + إشارات `supabase/sql/`).  
**القيود:** لا حذف جداول؛ أي توسعة مقترحة **nullable** و**backward compatible**.  
**التاريخ:** 2026-05-15

---

## 1) ملخص تنفيذي

| المحور | الوضع |
|--------|--------|
| **نواة المستخدم والعقار** | جداول ناضجة (`users_profiles`, `properties`, `org_units`, …) مع RLS مُوسَّع عبر عدة ترحيلات |
| **طبقة الامتثال `regc_*`** | موجودة: سياسات، قبول قانوني، شكاوى، تدقيق، أحداث أمن، موافقات كوكيز — انظر `20260515183000_compliance_legal_audit_rls.sql` |
| **نفاذ** | `nafath_logins` + Edge `nafath_session` — سجل خادمي؛ لا يعادل «هوية كاملة» على الملف |
| **فال** | حقول على `users_profiles` (امتثال) + `org_units` (كود عام + `fal_license_expires_at`) + Edge `verify_fal_license` (mock/استخراج HTML) |
| **REGA** | حمولات `rega_payload` على العقارات + لقطات تسويق — ليس تكاملاً رسمياً |
| **المدفوعات والاشتراكات** | `billing_transactions`, `user_subscriptions`, RPC تجديد تلقائي، Webhook ميسّر |
| **طاقم المنصة** | `platform_staff`, `is_platform_staff`, سياسات قراءة للموظف على الفوترة/الاشتراك |
| **جداول الطلب (regc_identity_profiles …)** | **غير منفّذة** كما سُميت في الطلب — انظر المصفوفة في `GOVERNMENT_FIELDS_MATRIX.md` |

---

## 2) جداول امتثال رئيسية (من الترحيلات)

- `regc_legal_policy_documents`, `regc_user_legal_acceptances`
- `regc_audit_logs` (إدراج عبر `compliance_append_audit`)
- `regc_user_complaints`, `regc_complaint_escalations`
- `regc_security_events`, `regc_incidents`, `regc_consent_preferences`
- تقييد `anon` على السطح الحساس: `20260516100000_compliance_revoke_anon_public_surface.sql`

---

## 3) فجوات مقارنةً بطلب «Government-Ready الكامل»

1. **لا يوجد جدول موحّد** لسجل التحقق الحكومي بكل الأنواع (نفاذ، فال، سجل تجاري، ناجز) بحقول `verification_provider_response` القياسية — الموجود مبعثر (JSON، جداول جزئية).
2. **لا محرك صلاحية منتهية** على مستوى Postgres واحد يربط كل الوثائق — المنطق جزئي في التطبيق (`ProfileComplianceService`, بوابات النشر).
3. **سجلات تدقيق شاملة** للأحداث المذكورة في الطلب (كل إجراء مع IP/JWT snapshot) **غير موحّدة** في جدول واحد؛ أجزاء في `regc_audit_logs` / جلسات / أخرى.
4. **أدوار المستخدم العشرة** في الطلب: التطبيق يدعم أنواع حساب **تسويق/مالك/فرد/منشآت** عبر `account_type`؛ **لا يوجد** تمييز صريح لـ «مشرف حكومي» أو «مراقب امتثال» كأنواع مستخدمين منفصلة — يُدار عبر `platform_staff` والصلاحيات المستقبلية للويب الإداري.

---

## 4) توصية التنفيذ

- **قبل العقود الرسمية:** تثبيت أن كل سكربتات `supabase/sql/` المطلوبة للإنتاج **أصبحت ترحيلات** (إن بقيت فجوة).
- **بعد العقود:** هجرة واحدة منظمة `regc_government_verifications` + توسيع `users_profiles`/`org_units` بأعمدة nullable فقط.

**نهاية التقرير.**
