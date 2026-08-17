# التقرير الختامي — الجاهزية الحكومية الشاملة

**التاريخ:** 2026-05-15  
**المنهجية:** مراجعة مستودع `aqar_user` (DB migrations + Edge + تطبيق Flutter/Web ضمنياً عبر الخدمات) — **بدون تعديل واجهة Home** و**بدون حذف جداول**.

---

## 1) نِسَب الجاهزية (تقديرية — للتخطيط وليست شهادة جهة)

| المؤشر | % | ملخص |
|--------|---|--------|
| **Government Readiness** | **62** | تصميم + بنية؛ نقص تكامل API رسمي وجداول هوية موحّدة |
| **Compliance Readiness** | **72** | طبقة `regc_*` قوية نسبياً + سياسات + شكاوى |
| **Security Readiness** | **74** | RLS واسع + تقييد anon + موظف منصة + جلسات/أجهزة |
| **Licensing Readiness (فال/682010)** | **58** | دعم تشغيلي؛ الاعتماد النهائي للجهة |

---

## 2) ما هو موجود (ملخص)

- **هوية وتسجيل:** `users_profiles` + مشغل `handle_new_user`؛ تحقق جزئي؛ أنواع حساب متعددة.
- **نفاذ:** `nafath_logins` + `nafath_session`.
- **فال:** حقول ملف/منشأة + Edge `verify_fal_license` (mock/استخراج).
- **REGA:** حمولات على العقار + تصميم مكتوب.
- **امتثال قانوني:** `regc_*` + `compliance_append_audit`.
- **مدفوعات/اشتراكات:** جداول كاملة + Webhook ميسّر + `subscription-renew-cron` + RPC تمديد.
- **موظفو المنصة:** `platform_staff` + سياسات قراءة للفوترة/الاشتراك.

---

## 3) المخاطر والنواقص

| الخطر | التخفيف المقترح |
|--------|------------------|
| حقول حكومية مبعثرة في JSON | جدول تحقق موحّد nullable بعد العقد |
| سكربتات في `supabase/sql/` دون ترحيل | تدقيق الإنتاج وتحويل الناقص إلى migrations |
| عدم وجود «مشرف حكومي» كنوع حساب | الإبقاء على ويب إداري منفصل + `platform_staff` / أدوار مستقبلية |
| ناجز/SBA غير مربوطين | لا تنفيذ قبل API keys |

---

## 4) ما يحتاج عقوداً رسمية أو بشرية

- عقود **REGA / نفاذ / ناجز / المركز السعودي للأعمال**.
- مراجعة **محامٍ** لنصوص `regc_legal_policy_documents` والمراجع في `docs/compliance/`.
- **PCI** وشهادات البوابة عند التشغيل الحي للبطاقات.

---

## 5) هجرات **مقترحة** (لا تُنفَّذ تلقائياً — للمراجعة ثم قرارك «طبّق»)

> الترتيب تقريبي؛ الأسماء اقتراحية.

1. `*_regc_government_verifications.sql` — جدول موحّد: `user_id`, `org_id`, `doc_type`, `status`, `issue_date`, `expiry_date`, `last_sync_at`, `provider_response jsonb`, `error text`.
2. `*_users_profiles_gov_identity_nullable.sql` — إضافة أعمدة الأفراد من المصفوفة (كلها nullable).
3. `*_org_units_commercial_nullable.sql` — أعمدة السجل التجاري والضريبة والبلدية (nullable).
4. `*_properties_deed_najiz_nullable.sql` — ربط صك/ناجز إن لزم.
5. `*_regc_compliance_alerts.sql` — طابور/جدول تنبيهات + فهرسة زمنية.
6. `*_audit_unified_append.sql` — RPC واحد يسجّل: `actor`, `target`, `action_type`, `ip`, `device`, `metadata` (مع الحذر من حجم JWT — تخزين hash أو claims مختصرة).

**ملاحظة:** الهجرات **`20260516140000`**, **`20260516150000`** الخاصة بالاشتراك التلقائي **منفّذة عندك** حسب رسالتك السابقة.

---

## 6) المراجع داخل الحزمة

- `DATABASE_COMPLIANCE_REPORT.md`
- `GOVERNMENT_FIELDS_MATRIX.md`
- `USER_IDENTITY_REQUIREMENTS.md`
- `REGA_READINESS_REPORT.md` + `REGA_INTEGRATION_DESIGN.md`
- `NAFATH_READINESS_REPORT.md` + `NAFATH_INTEGRATION_DESIGN.md`
- `NAJIZ_READINESS_REPORT.md`
- `PAYMENT_COMPLIANCE_REPORT.md`
- `LICENSE_EXPIRY_ENGINE_REPORT.md`

---

**الختام:** المنصة **جاهزة تشغيلياً وتجارياً** مع **أساس امتثال قوي**؛ التحويل إلى **Government-Ready كامل** يتطلب **هجرات الهوية الموحّدة + تكاملات API** بعد العقود. **لا يُنصح** بدمج كل شيء في تطبيق المستخدم — نظام الإدارة الويب المنفصل هو المكان الطبيعي لأدوار المراقبة والحكومي.

**نهاية التقرير الختامي.**
