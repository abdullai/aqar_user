# 🚀 دليل التنفيذ العملي - تكامل Wathq APIs

## 📋 فهرس المحتويات
1. [الإعدادات الأولية](#الإعدادات-الأولية)
2. [تطبيق الهجرات](#تطبيق-الهجرات)
3. [نشر Edge Functions](#نشر-edge-functions)
4. [دمج الخدمات في الكود](#دمج-الخدمات-في-الكود)
5. [اختبار التكامل](#اختبار-التكامل)
6. [استكشاف الأخطاء](#استكشاف-الأخطاء)

---

## 🔧 الإعدادات الأولية

### 1. الحصول على مفاتيح Wathq API

**من بوابة Wathq الرسمية:**
```
https://portal.wathq.sa
```

1. إنشاء حساب إن لم يكن لديك
2. إنشاء تطبيق جديد
3. نسخ المفتاح API

### 2. إضافة المفاتيح إلى الإعدادات

**في ملف `.env`:**
```bash
# === Wathq APIs ===
WATHQ_API_KEY=YOUR_WATHQ_API_KEY_HERE
WATHQ_API_BASE_URL=https://api.wathq.sa
WATHQ_API_TIMEOUT=30000
```

**أو في Supabase Secrets:**
```bash
supabase secrets set WATHQ_API_KEY "YOUR_WATHQ_API_KEY_HERE"
supabase secrets set WATHQ_API_BASE_URL "https://api.wathq.sa"
```

---

## 📊 تطبيق الهجرات

### 1. التحقق من وجود ملف الهجرة

```bash
cd D:\aqar_user
ls supabase/migrations/
```

يجب أن تجد:
```
20250610000000_wathq_integration_tables.sql
```

### 2. تطبيق الهجرة محلياً (إن أردت الاختبار أولاً)

```bash
# بدء Supabase محلياً
supabase start

# تطبيق الهجرة
supabase db push
```

### 3. تطبيق الهجرة في الإنتاج

```bash
# التحقق من الحالة
supabase db pull

# نشر التغييرات
supabase db push --remote
```

### ✅ التحقق من نجاح الهجرة

```sql
-- من Supabase Dashboard → SQL Editor
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
  'company_profiles',
  'company_addresses',
  'employee_information',
  'real_estate_deeds'
);
```

يجب أن ترى 4 جداول جديدة.

---

## 🚀 نشر Edge Functions

### 1. التحقق من الملف

```bash
ls supabase/functions/wathq_integration/
```

يجب أن تجد:
```
index.ts
```

### 2. اختبار محلياً

```bash
# بدء Supabase
supabase start

# في نافذة أخرى، اختبر الدالة
curl -X POST http://localhost:54321/functions/v1/wathq_integration \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "verify_user",
    "nationalId": "1234567890"
  }'
```

### 3. نشر الدالة

```bash
supabase functions deploy wathq_integration --remote
```

### 4. التحقق من النشر

```bash
# عرض السجلات
supabase functions list

# يجب أن ترى:
# wathq_integration    ACTIVE    https://[project-id].functions.supabase.co/functions/v1/wathq_integration
```

---

## 🔗 دمج الخدمات في الكود

### 1. استيراد الخدمات في `main.dart`

```dart
// lib/main.dart

import 'services/wathq_service.dart';
import 'services/integrated_verification_service.dart';

void main() async {
  // ... كود التهيئة الموجود ...

  // تهيئة Wathq Service
  final wathqService = WathqService(
    apiKey: dotenv.env['WATHQ_API_KEY'] ?? 'DEFAULT_KEY',
  );

  // تهيئة خدمة التحقق المتكاملة
  final verificationService = IntegratedVerificationService(
    wathqService: wathqService,
    nafathService: nafathAuthService, // من النافذ الموجود
  );

  // حفظها كـ Singletons (اختياري)
  Get.put(wathqService);
  Get.put(verificationService);

  runApp(const MyApp());
}
```

### 2. استخدام الخدمات في شاشة تسجيل الدخول

```dart
// lib/screens/login_screen.dart

class LoginScreenState extends State<LoginScreen> {
  late final WathqService wathqService;
  late final IntegratedVerificationService verificationService;

  @override
  void initState() {
    super.initState();
    wathqService = Get.find<WathqService>();
    verificationService = Get.find<IntegratedVerificationService>();
  }

  // عند النقر على زر "الدخول عبر نفاذ"
  Future<void> handleNafathLogin(String nationalId) async {
    try {
      showLoading('جاري التحقق...');

      // 1. بدء طلب نفاذ (موجود)
      // ... كود نفاذ الموجود ...

      // 2. بعد التحقق من نفاذ، حفظ بيانات المستخدم
      final userProfile = await verificationService.createOrUpdateUserFromNafath(
        nationalId: nationalId,
        userType: 'individual', // أو 'company'
        nafathData: nafathDataFromNafath,
      );

      hideLoading();

      // 3. تسجيل دخول ناجح
      Get.offAllNamed('/home');
    } catch (e) {
      hideLoading();
      showError('فشل التحقق: $e');
    }
  }
}
```

### 3. عرض بيانات المستخدم المجلوبة

```dart
// مثال في صفحة الملف الشخصي

class ProfileScreen extends StatefulWidget {
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final IntegratedVerificationService verificationService;
  late final WathqService wathqService;

  @override
  void initState() {
    super.initState();
    verificationService = Get.find();
    wathqService = Get.find();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // جلب بيانات المستخدم من Supabase
      final userData = await Supabase.instance.client
          .from('users_profiles')
          .select()
          .eq('id', userId)
          .single();

      // إذا كان شركة، اعرض بيانات الشركة
      if (userData['wathq_user_type'] == 'company') {
        _displayCompanyData(userId);
      } else {
        _displayIndividualData(userId);
      }
    } catch (e) {
      debugPrint('خطأ: $e');
    }
  }

  void _displayCompanyData(String userId) {
    // جلب بيانات الشركة
    Supabase.instance.client
        .from('company_profiles')
        .select()
        .eq('user_id', userId)
        .single()
        .then((data) {
          setState(() {
            // عرض البيانات
            companyName = data['company_name_ar'];
            crNumber = data['cr_number'];
            capital = data['capital'];
          });
        });

    // جلب العناوين
    Supabase.instance.client
        .from('company_addresses')
        .select()
        .eq('company_id', userId)
        .then((addresses) {
          setState(() {
            companyAddresses = addresses;
          });
        });
  }

  void _displayIndividualData(String userId) {
    // جلب بيانات الموظف
    Supabase.instance.client
        .from('employee_information')
        .select()
        .eq('user_id', userId)
        .single()
        .then((data) {
          setState(() {
            jobTitle = data['job_title'];
            employerName = data['employer_name'];
            salary = data['salary'];
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: ListView(
        children: [
          // عرض بيانات المستخدم
          if (userType == 'company')
            _buildCompanySection()
          else
            _buildIndividualSection(),
        ],
      ),
    );
  }
}
```

---

## 🧪 اختبار التكامل

### 1. اختبار الخدمة مباشرة

```dart
// اختبر في مشروع Dart/Flutter
void testWathqService() async {
  final wathqService = WathqService(
    apiKey: 'YOUR_WATHQ_API_KEY',
  );

  try {
    // اختبر جلب السجل التجاري
    final commercialData = await wathqService.getCommercialRegistration(
      crNumber: '1010711252', // استخدم رقم حقيقي للاختبار
    );
    print('✅ Commercial Data: $commercialData');

    // اختبر جلب العنوان
    final addresses = await wathqService.getNationalAddress(
      crNumber: '1010711252',
    );
    print('✅ Addresses: $addresses');

    // اختبر التحقق الشامل
    final verification = await wathqService.verifyUserData(
      unifiedId: '1010711252',
    );
    print('✅ Verification: ${verification.toJson()}');
  } catch (e) {
    print('❌ Error: $e');
  }
}
```

### 2. اختبر Edge Function

```bash
# استخدم Postman أو curl
curl -X POST https://[project-id].functions.supabase.co/functions/v1/wathq_integration \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "verify_user",
    "nationalId": "1234567890",
    "userId": "your-user-id"
  }'
```

### 3. اختبار تدفق كامل

```dart
void testCompleteFlow() async {
  final verificationService = IntegratedVerificationService(
    wathqService: wathqService,
    nafathService: nafathService,
  );

  try {
    // محاكاة بيانات نفاذ
    final nafathData = NafathUserData(
      fullName: 'محمد علي',
      nationalId: '1234567890',
      gender: 'M',
      birthDate: '1990-01-01',
    );

    // إنشاء المستخدم
    final userProfile = await verificationService.createOrUpdateUserFromNafath(
      nationalId: '1234567890',
      userType: 'individual',
      nafathData: nafathData,
    );

    print('✅ User created: ${userProfile.id}');
    print('✅ Wathq data: ${userProfile.wathqData}');

    // مزامنة البيانات
    await verificationService.syncUserDataWithWathq(userProfile.id!);
    print('✅ Data synced successfully');
  } catch (e) {
    print('❌ Error: $e');
  }
}
```

---

## 🔍 استكشاف الأخطاء

### المشكلة: "Wathq API غير متصل"

**السبب:** المفاتيح غير صحيحة أو الخادم معطل

**الحل:**
```bash
# تحقق من المفاتيح
echo $WATHQ_API_KEY

# جرّب الاتصال مباشرة
curl -H "Authorization: Bearer YOUR_KEY" \
  https://api.wathq.sa/sandbox/commercial-registration/fullinfo/1010711252
```

### المشكلة: "خطأ في تطبيق الهجرة"

**السبب:** الجداول موجودة بالفعل أو صرف الوصول

**الحل:**
```bash
# إسقاط الجداول (احذر!)
supabase db drop

# أو تجاهل الخطأ (الجداول موجودة)
# استخدم IF NOT EXISTS في الـ SQL
```

### المشكلة: "Edge Function لا تعمل"

**السبب:** المفاتيح غير مضبوطة أو الكود فيه خطأ

**الحل:**
```bash
# اعرض السجلات
supabase functions list
supabase functions logs wathq_integration

# أعد نشر الدالة
supabase functions deploy wathq_integration --remote
```

---

## 📝 قائمة التحقق

### قبل الإطلاق للإنتاج

- [ ] تم الحصول على مفاتيح Wathq API الحقيقية
- [ ] تم تطبيق الهجرات على Supabase الإنتاج
- [ ] تم نشر Edge Function
- [ ] تم اختبار التكامل مع أرقام حقيقية
- [ ] تم التحقق من RLS (Row Level Security)
- [ ] تم إضافة معالجة الأخطاء
- [ ] تم تسجيل العمليات (Logging)
- [ ] تم اختبار الأداء تحت الضغط

---

## 🎯 الخطوات التالية

1. **إضافة واجهات المستخدم:**
   - شاشة عرض بيانات الشركة
   - شاشة عرض بيانات الموظف
   - شاشة الصكوك العقارية

2. **تحسينات الأداء:**
   - تخزين مؤقت (Caching) للبيانات
   - مزامنة دورية تلقائية
   - معالجة الأخطاء المتقدمة

3. **الأمان:**
   - تشفير البيانات الحساسة
   - مراجعة سياسات RLS
   - تسجيل كل العمليات

4. **الاختبار:**
   - اختبار الوحدات (Unit Tests)
   - اختبار التكامل (Integration Tests)
   - اختبار الضغط (Load Tests)

---

**آخر تحديث:** الآن
**الحالة:** 🟢 جاهز للتطبيق
