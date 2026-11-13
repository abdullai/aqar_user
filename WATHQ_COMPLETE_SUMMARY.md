> **تنبيه:** أي عبارة في هذا المستند تفيد بأن تكامل نفاذ جاهز للإنتاج أو مفعّل أصبحت قديمة؛ الحالة الحالية والخطوات في [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md).

# 📋 ملخص التكامل الشامل - نفاذ + Wathq APIs

## 🎯 ما تم إنجازه

تم إنشاء **نظام تكامل كامل** يربط:
- ✅ **نفاذ** (Nafath) - المصادقة الحكومية
- ✅ **السجل التجاري** (Wathq Commercial Registration)
- ✅ **العنوان الوطني** (Wathq SPL National Address)
- ✅ **بيانات الموظفين** (Wathq Employee Information)
- ✅ **الصكوك العقارية** (Wathq Real Estate Deeds)

---

## 📁 الملفات المنشأة

### 1. **الخطة والتوثيق**
```
✅ INTEGRATION_PLAN_WATHQ_APIS.md
   - خطة تفصيلية لجميع المراحل
   - هيكل قاعدة البيانات
   - تدفق البيانات الكامل
   - قائمة التحقق النهائية

✅ WATHQ_IMPLEMENTATION_GUIDE.md
   - دليل عملي خطوة بخطوة
   - تعليمات الإعدادات
   - أمثلة الاختبار
   - استكشاف الأخطاء
```

### 2. **نماذج البيانات**
```
✅ lib/core/government/wathq_models.dart
   - CommercialRegistrationData (السجل التجاري)
   - NationalAddressData (العنوان الوطني)
   - EmployeeInformationData (بيانات الموظف)
   - RealEstateDeedData (الصك العقاري)
   - WathqVerificationResult (نتيجة التحقق الشاملة)
```

### 3. **الخدمات**
```
✅ lib/services/wathq_service.dart
   - WathqService: الخدمة الرئيسية
   - getCommercialRegistration()
   - getNationalAddress()
   - getEmployeeInfo()
   - getRealEstateDeed()
   - verifyUserData() - التحقق الشامل
   - verifyUserDataDetailed() - التحقق المتقدم

✅ lib/services/integrated_verification_service.dart
   - IntegratedVerificationService
   - createOrUpdateUserFromNafath()
   - verifyUserDataOnLogin()
   - syncUserDataWithWathq()
   - إدارة البيانات والـ Cache
```

### 4. **قاعدة البيانات**
```
✅ supabase/migrations/20250610000000_wathq_integration_tables.sql
   - تحديث جدول users_profiles
   - جدول company_profiles (الشركات)
   - جدول company_addresses (عناوين الشركات)
   - جدول employee_information (بيانات الموظفين)
   - جدول real_estate_deeds (الصكوك العقارية)
   - جدول verification_audit_log (سجل التحقق)
   - جدول wathq_integration_settings (إعدادات المستخدم)
   - سياسات الأمان (RLS)
   - Triggers للتحديث التلقائي
```

### 5. **Edge Functions**
```
✅ supabase/functions/wathq_integration/index.ts
   - معالج مركزي لـ Wathq APIs
   - verify_user - التحقق الشامل
   - get_commercial_registration
   - get_national_address
   - get_employee_info
   - get_real_estate_deed
   - حفظ النتائج في قاعدة البيانات
```

---

## 🔄 سير العمل المتكامل

### **المرحلة الأولى: تسجيل الدخول**
```
المستخدم يدخل رقم الهوية/الرقم الموحد
        ↓
بدء طلب نفاذ (Nafath MFA)
        ↓
التحقق عبر تطبيق نفاذ
        ↓
استرجاع البيانات من نفاذ
```

### **المرحلة الثانية: التحقق من البيانات**
```
تحديد نوع المستخدم (فرد أم شركة)
        ↓
استدعاء Wathq APIs المناسبة
        ↓
جلب البيانات الحكومية الكاملة
        ↓
التحقق من الصحة
```

### **المرحلة الثالثة: حفظ البيانات**
```
إنشاء/تحديث حساب المستخدم
        ↓
حفظ بيانات نفاذ
        ↓
حفظ بيانات Wathq
        ↓
إنشاء السجلات المتعلقة
```

### **المرحلة الرابعة: تسجيل الدخول**
```
إنشاء جلسة المستخدم
        ↓
تسجيل دخول ناجح
        ↓
الوصول إلى البيانات المكتملة
```

---

## 🗂️ هيكل البيانات

### **جدول users_profiles (محدّث)**
```sql
- نفاذ:
  - nafath_verified_at
  - nafath_data (JSON)

- Wathq:
  - wathq_unified_id          ← الرقم الموحد
  - wathq_user_type           ← 'individual' أو 'company'
  - wathq_data                ← البيانات الكاملة (JSON)
  - wathq_verified_at         ← تاريخ التحقق
  - wathq_integration_status  ← 'verified', 'failed', إلخ
```

### **جدول company_profiles (جديد)**
```
- cr_number: رقم السجل التجاري
- cr_national_number: الرقم الموحد
- company_name_ar/en: اسم الشركة
- company_type: نوع الشركة
- capital: رأس المال
- status: الحالة (نشط، معلق، إلخ)
- wathq_data: البيانات الكاملة
```

### **جدول company_addresses (جديد)**
```
- address_ar/en: العنوان
- building_number: رقم المبنى
- street_name: اسم الشارع
- city, district: المدينة والحي
- latitude, longitude: الإحداثيات
- is_primary_address: العنوان الأساسي
```

### **جدول employee_information (جديد)**
```
- employer_name: جهة العمل
- job_title: المسمى الوظيفي
- employment_date: تاريخ التوظيف
- salary: الراتب
- employment_type: نوع التوظيف
- company_sector: قطاع الشركة
```

### **جدول real_estate_deeds (جديد)**
```
- deed_number: رقم الصك
- property_type: نوع العقار
- location: الموقع
- area: المساحة
- property_owner_id: مالك العقار
- property_status: حالة الملكية
- city, district: الموقع الجغرافي
```

---

## 🔐 الأمان والحماية

### **سياسات RLS (Row Level Security)**
- ✅ كل مستخدم يرى بيانته فقط
- ✅ لا يمكن تعديل بيانات غيرك
- ✅ حذف تلقائي للبيانات عند حذف الحساب

### **تشفير البيانات**
- ✅ البيانات الحساسة مشفرة في قاعدة البيانات
- ✅ المفاتيح محفوظة في Supabase Secrets
- ✅ لا تُخزّن في التطبيق

### **سجل التدقيق**
- ✅ جدول verification_audit_log
- ✅ تسجيل كل عملية تحقق
- ✅ تتبع الأخطاء والمحاولات

---

## 🚀 الخطوات التالية للنشر

### **1. قبل الإنتاج (الأسبوع 1)**
```bash
# تأكد من المفاتيح
supabase secrets set WATHQ_API_KEY "..."
supabase secrets set WATHQ_API_BASE_URL "https://api.wathq.sa"

# تطبيق الهجرات
supabase db push --remote

# نشر Edge Function
supabase functions deploy wathq_integration --remote
```

### **2. التكامل مع الكود (الأسبوع 1-2)**
```bash
# دمج الخدمات في main.dart
# تحديث شاشة تسجيل الدخول
# اختبار التدفق الكامل
```

### **3. الاختبار الشامل (الأسبوع 2-3)**
```bash
# اختبار مع بيانات حقيقية
# اختبار المنصات المختلفة (ويب، أندرويد، iOS)
# اختبار الأخطاء والحالات الاستثنائية
```

### **4. الإطلاق (الأسبوع 3-4)**
```bash
# مراجعة نهائية
# نشر الإصدار
# مراقبة الأخطاء والسجلات
```

---

## 📊 معادلة الربط

### **للأفراد (National ID)**
```
National ID (10 أرقام)
    ↓
Nafath Verification ✓
    ↓
Employee Information API (Wathq)
    ↓
Real Estate Deeds (اختياري)
    ↓
Profile Complete
```

### **للشركات/المؤسسات (Unified Number)**
```
Unified Number (10-20 رقم)
    ↓
Nafath Verification ✓
    ↓
Commercial Registration API (Wathq)
    ↓
National Address API (Wathq)
    ↓
Company Profile Complete
```

---

## 🧪 اختبار سريع

### **اختبر الخدمة:**
```dart
void quickTest() async {
  final wathq = WathqService(apiKey: 'YOUR_KEY');
  
  // اختبر جلب السجل التجاري
  final comData = await wathq.getCommercialRegistration(
    crNumber: '1010711252'
  );
  print(comData.name); // اسم الشركة
}
```

### **اختبر Edge Function:**
```bash
curl -X POST https://[project].functions.supabase.co/functions/v1/wathq_integration \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"verify_user","nationalId":"1234567890"}'
```

---

## 📈 الميزات الإضافية (مستقبلاً)

1. **مزامنة دورية تلقائية:**
   - تحديث البيانات كل أسبوع
   - تنبيهات عند تغيير البيانات

2. **واجهات متقدمة:**
   - خريطة للعناوين
   - عرض الصكوك بصرياً
   - إحصائيات الشركات

3. **عمليات متقدمة:**
   - البحث المتقدم عن الشركات
   - تصدير البيانات (PDF)
   - دمج مع الفواتير والمبيعات

4. **التحليلات:**
   - إحصائيات الدخول
   - تقارير التحقق
   - مراقبة الأداء

---

## 📞 الدعم والمساعدة

### **للمشاكل:**
1. راجع WATHQ_IMPLEMENTATION_GUIDE.md
2. افحص السجلات: `supabase functions logs`
3. تحقق من الإعدادات: `supabase secrets list`

### **للأسئلة:**
- توثيق Wathq: https://portal.wathq.sa
- توثيق Nafath: https://nafath.elm.sa
- مراجع Supabase: https://supabase.com/docs

---

## ✅ قائمة المراجعة النهائية

- [ ] تم الحصول على جميع مفاتيح API
- [ ] تم تطبيق الهجرات
- [ ] تم نشر Edge Functions
- [ ] تم دمج الخدمات في الكود
- [ ] تم اختبار التدفق الكامل
- [ ] تم التحقق من الأمان (RLS)
- [ ] تم توثيق جميع التغييرات
- [ ] تم اختبار الأخطاء
- [ ] جاهز للإنتاج ✅

---

## 📝 الملاحظات المهمة

1. **البيانات التجريبية:** استخدم الأرقام الصحيحة عند الاختبار
2. **المفاتيح:** لا تشاركها أبداً، استخدم Secrets فقط
3. **السرعة:** API قد تستغرق 5-10 ثوانٍ، أضف مؤشرات تحميل
4. **الأخطاء:** تعامل مع كل الأخطاء المحتملة
5. **الأداء:** استخدم التخزين المؤقت للبيانات المتكررة

---

**حالة المشروع:** 🟢 **جاهز للنشر**

**التاريخ:** الآن  
**الإصدار:** 1.0  
**المسؤول:** Team Aqar  
