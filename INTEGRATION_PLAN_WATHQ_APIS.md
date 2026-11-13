> **تنبيه:** أي عبارة في هذا المستند تفيد بأن تكامل نفاذ جاهز للإنتاج أو مفعّل أصبحت قديمة؛ الحالة الحالية والخطوات في [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md).

> **تنبيه أمني ونفاذ:** حُذفت قيمة اعتماد قديمة من هذا الملف. لا تستخدم هذا الدليل كتعليمات إنتاج؛ راجع [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md) للحالة الحالية، ولا تضع الأسرار في التطبيق أو المستودع.

# 📋 خطة تكامل APIs الوثائق السعودية الشاملة (Wathq APIs)

## 🎯 نظرة عامة

سيتم ربط **أربع خدمات حكومية** مع نظام **نفاذ** لإنشاء تجربة تسجيل دخول وتحقق متكاملة:

| API | الاستخدام | البيانات الرئيسية |
|-----|----------|-----------------|
| **Wathq Commercial Registration** | التحقق من الشركات والمؤسسات | رقم السجل التجاري / الرقم الموحد |
| **Wathq SPL National Address** | جلب عنوان الشركة | العنوان الوطني + الإحداثيات |
| **Wathq Employee Information** | التحقق من بيانات الموظف | بيانات العمل والراتب والعلاقات |
| **Wathq Real Estate Deeds** | التحقق من الصكوك العقارية | بيانات الملكية والعقار |

---

## 🔗 سير العمل المتكامل

### **المرحلة 1️⃣: تسجيل الدخول عبر نفاذ**

```
الدخول برقم الهوية الموحد
    ↓
بدء طلب نفاذ MFA
    ↓
التحقق عبر تطبيق نفاذ
    ↓
استرجاع بيانات نفاذ (رقم الهوية الموحد)
    ↓
البحث في قاعدة البيانات
```

### **المرحلة 2️⃣: التحقق من نوع المستخدم**

```
هل المستخدم فرد أم مؤسسة؟
│
├─ إذا كان الرقم رقم هوية وطني (نفاذ للأفراد)
│   └─ الذهاب إلى: جلب بيانات الموظف + الصكوك
│
└─ إذا كان الرقم موحد للشركات/المؤسسات (نفاذ للشركات)
    └─ الذهاب إلى: جلب بيانات السجل التجاري
```

### **المرحلة 3️⃣: جلب البيانات الإضافية**

#### **للأفراد (رقم الهوية الوطني)**
```
استدعاء: Wathq Employee Information API
Input:  رقم الهوية من نفاذ
Output: 
  - اسم الموظف
  - جهة العمل
  - الراتب والعقد
  - تاريخ التوظيف
```

#### **للشركات/المؤسسات (الرقم الموحد)**
```
استدعاء: Wathq Commercial Registration API
Input:  الرقم الموحد / رقم السجل التجاري
Output:
  - اسم الشركة
  - نوع الشركة (LLC, شركة مساهمة، إلخ)
  - المالك والشركاء
  - تاريخ التسجيل
  - الحالة (فعال، معلق، إلخ)
  - رأس المال

ثم استدعاء: Wathq SPL National Address API
Input:  رقم السجل التجاري / الرقم الموحد
Output:
  - العنوان الوطني الكامل
  - الإحداثيات (Latitude, Longitude)
  - اسم المنطقة والمدينة
  - رقم الفرع
```

#### **للعقارات والصكوك (اختياري)**
```
استدعاء: Wathq Real Estate Deeds API
Input:  رقم الصك + رقم الهوية + نوع الهوية
Output:
  - بيانات العقار
  - المالك الحالي
  - المساحة والموقع
  - حالة الصك
  - تاريخ الصك
```

### **المرحلة 4️⃣: إنشاء/تحديث حساب المستخدم**

```
جميع البيانات المجلوبة
    ↓
تخزينها في جداول قاعدة البيانات
    ↓
ربط هوية نفاذ بحساب المستخدم
    ↓
إنشاء ملف تفصيلي مكمل
    ↓
تسجيل دخول ناجح
```

---

## 💾 هيكل قاعدة البيانات المطلوب

### **جدول 1: `users_profiles` (محدّث)**
```sql
-- أعمدة نفاذ الموجودة
- id (UUID)
- email
- phone
- nafath_verified_at
- nafath_data (JSON)
- auth_method ('traditional', 'nafath')

-- إضافة أعمدة جديدة للتكامل
+ wathq_unified_id VARCHAR(20)           -- الرقم الموحد
+ wathq_user_type VARCHAR(20)            -- 'individual' أو 'company'
+ wathq_data JSON                        -- بيانات Wathq الكاملة
+ wathq_verified_at TIMESTAMP            -- تاريخ التحقق
+ wathq_integration_status VARCHAR(50)   -- 'pending', 'verified', 'failed'
```

### **جدول 2: `company_profiles` (جديد)**
```sql
CREATE TABLE company_profiles (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users_profiles(id),
  cr_number VARCHAR(20),                 -- رقم السجل التجاري
  cr_national_number VARCHAR(20),        -- الرقم الموحد
  company_name_ar VARCHAR(255),
  company_name_en VARCHAR(255),
  company_type VARCHAR(100),             -- LLC, شركة مساهمة، إلخ
  headquarters_city VARCHAR(100),
  capital DECIMAL(15,2),
  company_duration INTEGER,              -- سنة
  status VARCHAR(50),                    -- 'active', 'suspended', 'liquidating'
  has_ecommerce BOOLEAN,
  issue_date TIMESTAMP,
  wathq_data JSON,                       -- البيانات الكاملة من API
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### **جدول 3: `company_addresses` (جديد)**
```sql
CREATE TABLE company_addresses (
  id UUID PRIMARY KEY,
  company_id UUID REFERENCES company_profiles(id),
  address_ar VARCHAR(500),
  address_en VARCHAR(500),
  building_number VARCHAR(50),
  street_name VARCHAR(200),
  district VARCHAR(100),
  city VARCHAR(100),
  postal_code VARCHAR(10),
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  is_primary_address BOOLEAN DEFAULT TRUE,
  wathq_data JSON,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### **جدول 4: `employee_information` (جديد)**
```sql
CREATE TABLE employee_information (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users_profiles(id),
  national_id VARCHAR(20),
  employer_name VARCHAR(255),
  job_title VARCHAR(200),
  employment_date TIMESTAMP,
  salary DECIMAL(12,2),
  employment_type VARCHAR(50),           -- 'full_time', 'contract', إلخ
  employment_status VARCHAR(50),         -- 'active', 'inactive'
  company_sector VARCHAR(100),
  wathq_data JSON,                       -- البيانات الكاملة من API
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### **جدول 5: `real_estate_deeds` (جديد)**
```sql
CREATE TABLE real_estate_deeds (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users_profiles(id),
  deed_number VARCHAR(50),
  deed_serial VARCHAR(50),
  property_owner_id VARCHAR(20),
  owner_type VARCHAR(50),                -- 'National_ID', 'CR_NO', إلخ
  property_type VARCHAR(100),
  location VARCHAR(500),
  area DECIMAL(12,2),                    -- المساحة بالمتر المربع
  deed_date TIMESTAMP,
  property_status VARCHAR(50),
  municipality_sector VARCHAR(100),
  wathq_data JSON,                       -- البيانات الكاملة من API
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

---

## 🔑 إعدادات المفاتيح والمصادقة

### **.env أو Supabase Secrets**

```bash
# === Nafath (موجود) ===
NAFATH_INTEGRATION_ENABLED=true
NAFATH_URL_BASE=https://mock-service.api.elm.sa/nafath
NAFATH_API_KEY=REDACTED
NAFATH_APP_ID=wl7j5rdg
NAFATH_APP_KEY=REDACTED_ROTATE_EXPOSED_KEY

# === Wathq APIs (جديد) ===
WATHQ_API_BASE_URL=https://api.wathq.sa
WATHQ_API_KEY=YOUR_WATHQ_API_KEY_HERE           # من بوابة Wathq
WATHQ_API_TIMEOUT=30000                         # 30 ثانية
WATHQ_RETRY_ATTEMPTS=3

# === تكامل التحقق ===
VERIFY_WATHQ_ON_NAFATH_LOGIN=true              # تفعيل التحقق التلقائي
VERIFY_WATHQ_REQUIRED_FOR_POSTING=true         # إلزامي لنشر العقارات
CACHE_WATHQ_DATA_DAYS=30                       -- تخزين مؤقت لـ 30 يوم
```

---

## 🛠️ الملفات والخدمات المطلوبة

### **1. خدمة Wathq المركزية**
**ملف:** `lib/services/wathq_service.dart`

```dart
class WathqService {
  // تحقق من السجل التجاري والمؤسسة
  Future<CommercialRegistrationData> getCommercialRegistration(String crNumber);
  
  // جلب العنوان الوطني
  Future<List<NationalAddressData>> getNationalAddress(String crNumber);
  
  // جلب بيانات الموظف
  Future<EmployeeInformationData> getEmployeeInfo(String nationalId);
  
  // جلب بيانات الصك العقاري
  Future<RealEstateDeedData> getRealEstateDeed(
    String deedNumber,
    String idNumber,
    String idType,
  );
  
  // التحقق من جميع البيانات
  Future<VerificationResult> verifyAllData({
    required String unifiedId,
    required String userType, // 'individual' or 'company'
  });
}
```

### **2. نماذج البيانات**
**ملف:** `lib/core/government/wathq_models.dart`

```dart
// السجل التجاري
class CommercialRegistrationData {
  String crNumber;
  String crNationalNumber;
  String name;
  String? nameEn;
  String? status;
  String? companyType;
  DateTime? issueDate;
  int? capital;
  List<Partner>? partners;
  // ... المزيد من الحقول
}

// العنوان الوطني
class NationalAddressData {
  String addressAr;
  String? addressEn;
  String city;
  String district;
  String? buildingNumber;
  String? street;
  double? latitude;
  double? longitude;
  bool isPrimaryAddress;
}

// بيانات الموظف
class EmployeeInformationData {
  String nationalId;
  String employerName;
  String jobTitle;
  DateTime employmentDate;
  double? salary;
  String employmentType;
  String? companySector;
}

// الصك العقاري
class RealEstateDeedData {
  String deedNumber;
  String propertyType;
  String location;
  double area;
  DateTime deedDate;
  String propertyOwner;
  String? propertyStatus;
}

// نتيجة التحقق الشاملة
class VerificationResult {
  bool isVerified;
  String userType; // 'individual' or 'company'
  CommercialRegistrationData? commercialData;
  NationalAddressData? addressData;
  EmployeeInformationData? employeeData;
  RealEstateDeedData? deedData;
  DateTime verifiedAt;
}
```

### **3. خدمة التحقق المتكاملة**
**ملف:** `lib/services/integrated_verification_service.dart`

```dart
class IntegratedVerificationService {
  // ربط نفاذ مع Wathq
  Future<UserProfile> createOrUpdateUserFromNafath({
    required String nationalId,
    required String userType,
    required NafathUserData nafathData,
  });
  
  // التحقق التلقائي عند الدخول
  Future<void> verifyUserDataOnLogin(String userId);
  
  // جلب وتحديث البيانات
  Future<void> syncUserDataWithWathq(String userId);
}
```

### **4. Edge Function محدّثة**
**ملف:** `supabase/functions/nafath_session/index.ts`

```typescript
// إضافة استدعاء Wathq بعد التحقق من نفاذ
async function handleNafathCallback() {
  // 1. تحقق من نفاذ (موجود)
  // 2. جديد: استدعِ Wathq لجلب البيانات
  // 3. حفظ البيانات في قاعدة البيانات
  // 4. إنشاء الحساب إذا لم يكن موجوداً
}
```

---

## 📱 تعديلات شاشة تسجيل الدخول

### **شاشة تسجيل الدخول المحدّثة**
**ملف:** `lib/screens/login_screen.dart`

```dart
// المسار الموحد:
// أدخل الرقم الموحد (هوية / رقم سجل تجاري)
//     ↓
// انقر: "الدخول عبر نفاذ"
//     ↓
// يتم التحقق وجلب البيانات تلقائياً
//     ↓
// إذا جديد: ملء البيانات الناقصة (اختياري)
//     ↓
// ✅ دخول ناجح
```

---

## 🗂️ هيكل المشروع المقترح

```
lib/
├── core/
│   └── government/
│       ├── nafath_models.dart         ✅ (موجود)
│       ├── wathq_models.dart          🆕 (جديد)
│       └── verification_models.dart   🆕 (جديد)
│
├── services/
│   ├── nafath_auth_service.dart       ✅ (موجود)
│   ├── wathq_service.dart             🆕 (جديد)
│   └── integrated_verification_service.dart  🆕 (جديد)
│
├── screens/
│   └── login_screen.dart              ✅ (محدّث)
│
└── widgets/
    ├── nafath_login_sheet.dart        ✅ (موجود)
    └── wathq_verification_sheet.dart  🆕 (اختياري)

supabase/
├── functions/
│   ├── nafath_session/
│   │   └── index.ts                   ✅ (محدّث)
│   └── wathq_integration/             🆕 (جديد)
│       └── index.ts
│
└── migrations/
    ├── 20260605000000_nafath_integration_user_attributes.sql  ✅
    └── 20260610000000_wathq_integration_tables.sql           🆕
```

---

## ⚙️ خطوات التنفيذ

### **الخطوة 1️⃣: الإعدادات والمفاتيح**
- [ ] الحصول على مفاتيح Wathq API من البوابة
- [ ] إضافة المفاتيح إلى `.env` و Supabase Secrets
- [ ] اختبار الاتصال بـ Wathq APIs

### **الخطوة 2️⃣: إنشاء قاعدة البيانات**
- [ ] إنشاء migrations للجداول الجديدة
- [ ] تطبيق الهجرات على Supabase
- [ ] التحقق من الجداول

### **الخطوة 3️⃣: بناء الخدمات**
- [ ] إنشاء `wathq_service.dart`
- [ ] إنشاء `wathq_models.dart`
- [ ] إنشاء `integrated_verification_service.dart`

### **الخطوة 4️⃣: تحديث Edge Functions**
- [ ] محدّث `nafath_session/index.ts` لاستدعاء Wathq
- [ ] إنشاء `wathq_integration/index.ts`
- [ ] نشر الدوال على Supabase

### **الخطوة 5️⃣: تحديث الواجهات**
- [ ] تعديل `login_screen.dart`
- [ ] تحديث `nafath_login_sheet.dart`
- [ ] إضافة مؤشر التحميل للبيانات الإضافية

### **الخطوة 6️⃣: الاختبار والتحقق**
- [ ] اختبار دخول فرد (رقم هوية)
- [ ] اختبار دخول شركة (رقم سجل تجاري)
- [ ] اختبار جلب البيانات
- [ ] التحقق من حفظ البيانات في قاعدة البيانات

---

## 🔍 تدفق البيانات الكامل

```
┌─────────────────────────────────────────────────────┐
│  شاشة تسجيل الدخول                                  │
│  "أدخل الرقم الموحد"                               │
└────────────────┬────────────────────────────────────┘
                 │
                 ↓
         ┌───────────────┐
         │  خدمة نفاذ    │
         │ (Nafath MFA)  │
         └───────┬───────┘
                 │
      ✓ تحقق ناجح
                 │
                 ↓
    ┌─────────────────────────┐
    │ تحديد نوع المستخدم      │
    │ (فرد / شركة / إلخ)      │
    └────────┬────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ↓                 ↓
┌─────────────┐  ┌─────────────────────┐
│ فرد:        │  │ شركة/مؤسسة:         │
│ - بيانات   │  │ - السجل التجاري      │
│   الموظف   │  │ - العنوان الوطني    │
│ - صكوك     │  │ - بيانات المالك     │
│   عقارية   │  └────────┬────────────┘
└──────┬─────┘           │
       │          ┌──────┴──────────────┐
       │          │                     │
       ↓          ↓                     ↓
    [WATHQ]   [WATHQ]              [WATHQ]
    Employee  Commercial          SPL Address
    API       Registration API    API
       │          │                │
       └──────────┼────────────────┘
              │
              ↓
    ┌───────────────────────┐
    │ قاعدة البيانات        │
    │ (تخزين البيانات)      │
    └───────┬───────────────┘
            │
            ↓
    ┌───────────────────────┐
    │ ✅ تسجيل دخول ناجح    │
    │ حساب مكتمل البيانات   │
    └───────────────────────┘
```

---

## 📊 حالة البيانات المتوقعة

### **مثال 1: دخول فرد (رقم الهوية)**

```json
{
  "nationalId": "1234567890",
  "userType": "individual",
  "nafathData": {
    "fullName": "محمد علي",
    "nationalId": "1234567890"
  },
  "employeeData": {
    "employerName": "شركة XYZ",
    "jobTitle": "مهندس",
    "salary": 5000,
    "employmentDate": "2020-01-15"
  },
  "realEstateDeeds": [
    {
      "deedNumber": "123456",
      "propertyType": "سكني",
      "area": 250
    }
  ]
}
```

### **مثال 2: دخول شركة (الرقم الموحد)**

```json
{
  "unifiedId": "7001234567",
  "userType": "company",
  "nafathData": {
    "companyName": "شركة الأحلام للتطوير"
  },
  "commercialRegistrationData": {
    "crNumber": "1010711252",
    "crNationalNumber": "7001234567",
    "companyType": "ذات مسؤولية محدودة",
    "capital": 500000,
    "status": "active"
  },
  "addressData": {
    "addressAr": "شارع الملك فهد - الرياض",
    "city": "الرياض",
    "latitude": 24.75,
    "longitude": 46.67
  }
}
```

---

## ✅ قائمة التحقق النهائية

- [ ] جميع مفاتيح API محفوظة بأمان
- [ ] جداول قاعدة البيانات منشأة
- [ ] خدمات Wathq مطبوقة
- [ ] Edge Functions محدثة
- [ ] واجهات المستخدم محدثة
- [ ] تم الاختبار على أرقام تجريبية
- [ ] تم التحقق من حفظ البيانات
- [ ] وثائق معدلة
- [ ] جاهز للإنتاج ✅

---

**آخر تحديث:** الآن
**الحالة:** 📋 جاهز للبدء في التنفيذ
**الأولوية:** عالية جداً
