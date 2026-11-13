> **تنبيه:** أي عبارة في هذا المستند تفيد بأن تكامل نفاذ جاهز للإنتاج أو مفعّل أصبحت قديمة؛ الحالة الحالية والخطوات في [NAFATH_PRODUCTION_DEPLOYMENT.md](./NAFATH_PRODUCTION_DEPLOYMENT.md).

# 🚀 دليل التنفيذ الشامل - Wathq + Nafath Integration

## ✅ المرحلة 1: الإعدادات الأولية

### 1.1 الحصول على مفاتيح Wathq API

1. زر بوابة Wathq: https://portal.wathq.sa
2. سجّل دخولك أو أنشئ حساباً جديداً
3. انتقل إلى **الإعدادات** → **API Keys**
4. انسخ المفاتيح التالية:
   - `WATHQ_API_KEY` - مفتاح API الخاص بك
   - `WATHQ_API_BASE_URL` - عادة `https://api.wathq.sa`

### 1.2 إضافة المفاتيح إلى Supabase

```bash
# اذهب إلى مجلد المشروع
cd D:\aqar_user

# تسجيل دخول Supabase
supabase login

# أضف المفاتيح
supabase secrets set WATHQ_API_KEY "YOUR_ACTUAL_API_KEY_HERE"
supabase secrets set WATHQ_API_BASE_URL "https://api.wathq.sa"
supabase secrets set WATHQ_COMMERCIAL_ENDPOINT "/api/v1/commercial-registration"
supabase secrets set WATHQ_NATIONAL_ADDRESS_ENDPOINT "/api/v1/national-address"
supabase secrets set WATHQ_EMPLOYEE_INFO_ENDPOINT "/api/v1/employee-information"
supabase secrets set WATHQ_REAL_ESTATE_ENDPOINT "/api/v1/real-estate-deeds"

# تحقق من المفاتيح
supabase secrets list
```

### 1.3 تطبيق الهجرات على قاعدة البيانات

```bash
# تطبيق جميع الهجرات
supabase db push --remote

# إذا حدث خطأ، ألغِ التغييرات
supabase db push --force --remote
```

## ✅ المرحلة 2: نشر Edge Functions

### 2.1 إنشاء ومراجعة Edge Function

```bash
# انظر إلى الملف الموجود
cat supabase/functions/wathq_integration/index.ts

# تأكد من أن جميع المفاتيح الضرورية موجودة في الملف
```

### 2.2 نشر الدالة

```bash
# نشر Edge Function
supabase functions deploy wathq_integration --remote

# اختبر الدالة
curl -i --request POST 'https://YOUR_PROJECT_ID.supabase.co/functions/v1/wathq_integration' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{
    "action": "get_commercial_registration",
    "unified_id": "1234567890123"
  }'
```

## ✅ المرحلة 3: التحقق من Dart Dependencies

```bash
# تحديث المشروع
flutter pub get

# تحقق من عدم وجود أخطاء
flutter analyze

# إصلاح الأخطاء تلقائياً (إن أمكن)
dart fix --apply
```

## ✅ المرحلة 4: دمج الخدمات في المشروع

### 4.1 تحديث main.dart

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/services/wathq_service.dart';
import 'lib/services/integrated_verification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  // تهيئة الخدمات
  final wathqService = WathqService(Supabase.instance.client);
  final verificationService = IntegratedVerificationService(
    wathqService: wathqService,
    supabase: Supabase.instance.client,
  );

  print('✅ تم تهيئة جميع الخدمات');

  runApp(const MyApp());
}
```

### 4.2 تحديث شاشة الدخول

انظر إلى: `lib/examples/wathq_usage_examples.dart`

استخدم الفئة `LoginScreenExample` كمثال لدمج الدخول عبر نفاذ.

### 4.3 إضافة الصفحات المطلوبة

1. **صفحة بيانات الشركة:** انظر `CompanyProfilePageExample`
2. **صفحة بيانات الموظف:** انظر `EmployeeProfilePageExample`
3. **صفحة الصكوك العقارية:** انظر التوثيق الكاملة

## ✅ المرحلة 5: الاختبار

### 5.1 اختبار التدفق الكامل

```bash
# 1. شغّل التطبيق
flutter run -d chrome

# 2. ادخل رقم موحد تجريبي
# الأفراد: 1234567890 (10 أرقام)
# الشركات: 123456789012345 (15 رقم)

# 3. تحقق من السجلات
flutter logs
```

### 5.2 اختبار على جميع المنصات

```bash
# الويب
flutter run -d chrome

# أندرويد
flutter run -d emulator-5554

# iOS (macOS فقط)
flutter run -d simulator
```

### 5.3 اختبار معالجة الأخطاء

- اختبر بأرقام غير صحيحة
- اختبر بدون اتصال إنترنت
- اختبر Timeout (قطع الاتصال)
- اختبر مع أرقام بيانات مفقودة

## ✅ المرحلة 6: النشر للإنتاج

### 6.1 مراجعة أمان

```bash
# تحقق من عدم وجود مفاتيح في الكود
grep -r "WATHQ_API_KEY" lib/
grep -r "WATHQ_API_BASE_URL" lib/

# يجب أن يكون الناتج فارغاً
```

### 6.2 بناء الإصدار النهائي

```bash
# الويب
flutter build web

# أندرويد
flutter build apk --release

# iOS (macOS فقط)
flutter build ipa
```

### 6.3 نشر على المتاجر

- **Play Store:** انظر التوثيق الرسمية
- **App Store:** انظر التوثيق الرسمية
- **Web:** استضيف على Firebase أو Netlify

## 📊 قائمة التحقق

### قبل الاختبار
- [ ] تم إضافة مفاتيح Wathq إلى Supabase Secrets
- [ ] تم تطبيق الهجرات على قاعدة البيانات
- [ ] تم نشر Edge Function
- [ ] تم تحديث main.dart
- [ ] تم تشغيل `flutter pub get`

### قبل النشر
- [ ] اختبر على الويب بنجاح
- [ ] اختبر على أندرويد بنجاح
- [ ] اختبر على iOS بنجاح (إن أمكن)
- [ ] تحقق من عدم وجود مفاتيح في الكود
- [ ] اختبر معالجة الأخطاء الكاملة
- [ ] راجع سياسات الأمان (RLS)

## 🔧 استكشاف الأخطاء

### خطأ: "Unknown method .get_commercial_registration"
**الحل:** تحقق من أن Edge Function تم نشرها بنجاح
```bash
supabase functions list
supabase functions download wathq_integration
```

### خطأ: "No WATHQ_API_KEY in secrets"
**الحل:** أضف المفاتيح إلى Supabase Secrets
```bash
supabase secrets list
supabase secrets set WATHQ_API_KEY "..."
```

### خطأ: "Column 'id' referenced in foreign key constraint"
**الحل:** تأكد من أن الهجرات تم تطبيقها بالترتيب الصحيح
```bash
supabase migration list --remote
supabase db push --remote
```

### خطأ: "RLS policy violation"
**الحل:** تحقق من سياسات RLS
```bash
select * from public.company_profiles;  -- من Supabase Dashboard
```

## 📞 للمساعدة

- 📧 البريد الإلكتروني: support@wathq.sa
- 📖 التوثيق: https://docs.wathq.sa
- 💬 المنتدى: https://forum.wathq.sa

---

**آخر تحديث:** 2024
**الحالة:** جاهز للإنتاج ✅
