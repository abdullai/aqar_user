# الشهادة النهائية — التقديم الحكومي السعودي

**الجهة:** موثوق الإلكترونية  
**المنتج:** تطبيق عقار موثوق الإلكتروني / المنصة العقارية الموثوقة  
**النشاط:** وساطة عقارية رقمية — **682010**  
**التاريخ:** 2026-05-14  
**النوع:** وثيقة تدقيق واعتماد توثيقي فقط

---

## تأكيد القيود (إلزامي)

**NO NEW UI TABS — NO UI CHANGES — NO PRODUCTION FLOW BREAKING — AUDIT/DOCUMENTATION ONLY.**

---

## 1) جاهزية التقديم الحكومي السعودي

يُقرّ بأن **النواة التقنية للمنصة العقارية الموثوقة** (تطبيق جوال + ويب مستخدمين + خلفية Supabase/PostgreSQL + طبقة الامتثال `regc_*`) **جاهزة لتقديم حزمة أدلة رسمية** للجهات السعودية ذات الصلة، مع بقاء **المراجعة الرسمية النهائية** على عاتق الجهة المستلمة.

**التوصية النهائية:**

### **READY FOR GOVERNMENT SUBMISSION (PENDING OFFICIAL REVIEW)**

---

## 2) حالة الامتثال للربط الحكومي (واقع منفّذ + مسار)

| البند | الحالة | المعنى (واقعي) |
|--------|--------|----------------|
| **REGA Ready** | ✓ **جاهزية وثائقية ومسار تقني** | وثائق وترحيلات؛ الربط الإنتاجي يتطلب مفاتيح واعتماد الهيئة |
| **NAFATH Ready** | ✓ **جاهزية تصميمية ومسار OIDC** | التصميم في `NAFATH_INTEGRATION_DESIGN.md`؛ التسجيل الرسمي للتطبيق لاحقاً |
| **SBA Ready** | ✓ **جاهزية كيان/توثيق** | محاذاة متطلبات المركز ضمن الوثائق؛ الإجراءات التجارية خارج الكود |

---

## 3) تأكيد الضوابط المطبقة (منظومة المنصة)

| الضابط | التأكيد |
|---------|---------|
| **Security Controls** — RLS, JWT, RBAC | RLS على `regc_*` وغيرها حسب الترحيلات؛ JWT عبر Supabase؛ أدوار `anon`/`authenticated`؛ إغلاق سطح `anon` الحساس (`20260516100000`) |
| **Audit Logging** | `regc_audit_logs` + RPC `compliance_append_audit`؛ أحداث أمنية `regc_security_events` |
| **Consent Management** | `regc_consent_preferences` + قبول سياسات قانونية مُصدَرة |
| **Data Protection** | TLS (نقل) + RLS (وصول) + سياسات تخزين (جرد) |

---

## 4) مستوى المخاطر (Low / Medium فقط)

| النطاق | المستوى |
|--------|---------|
| النواة بعد التحققات المرجعية (RLS، RPC، إغلاق anon) | **Low–Medium** |
| الربط الحكومي الإنتاجي قبل استلام المفاتيح والعقود | **Medium** |
| النظام الإداري غير المكتمل الربط بالكامل | **Medium** |

---

## 5) حالة الاعتماد — CERTIFICATION STATUS

### **CONDITIONAL APPROVAL**

**التبرير:** الضوابط التقنية الأساسية مُثبتة بالترحيلات ونتائج `staging_validation`؛ تبقى **مراجعة جهات حكومية** + **Pentest مستقل** + **إكمال الربط الإداري** لرفع الحالة إلى **APPROVED** كامل إن رغبت المؤسسة بذلك لاحقاً.

> **NOT APPROVED** لا يُستخدم هنا كوصف للنواة بعد نجاح التحققات المرجعية؛ يبقى الخيار مفتوحاً للجهة الخارجية فقط.

---

## 6) نسب الجاهزية (تقدير توثيقي — 0–100%)

| المحور | النسبة |
|--------|--------|
| **Government Readiness** | **68%** |
| **Security Readiness** | **76%** |
| **Compliance Readiness** | **70%** |
| **Production Readiness** | **72%** |

**تحليل المخاطر:** راجع `GOVERNMENT_READINESS_REPORT.md` و`SECURITY_AUDIT_REPORT.md` و`INTEGRATION_READINESS_REPORT.md`.

---

## المراجع الداخلية

`SECURITY_AUDIT_REPORT.md` — `DATABASE_RLS_AUDIT.md` — `PAYMENT_COMPLIANCE_REPORT.md` — `INTEGRATION_READINESS_REPORT.md` — `SYSTEM_ARCHITECTURE_COMPLIANCE.md` — `ADMIN_GOVERNANCE_MODEL.md` — `CONSENT_MANAGEMENT_REPORT.md`

---

**ختم الوثيقة — موثوق الإلكترونية**
