# موثوق لاين العقارية

منصة عقارية Flutter متعددة المنصات، تعتمد على Supabase للمصادقة والبيانات
والتخزين وRealtime، وعلى Firebase للإشعارات، مع تكامل تجريبي للدفع والتحقق
من تراخيص REGA.

## الحالة الحالية

المشروع في مرحلة التطوير والتجربة. رمز التحقق الداخلي يعمل من خلال إشعار داخل
التطبيق، والدفع الوهمي يعمل في Debug فقط عند عدم ضبط مفتاح Moyasar. لا تعتبر
هذه الإعدادات جاهزة للإنتاج.

## التشغيل المحلي

المتطلبات:

- Flutter/Dart المتوافقان مع القيد الموجود في `pubspec.yaml`.
- Node.js إذا كان مطلوباً تشغيل `fal_backend`.
- Supabase CLI عند تشغيل قاعدة بيانات محلية أو تطبيق migrations.

الأوامر الأساسية:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

للتطوير انسخ `env.sample` إلى `.env`، ثم ضع مفتاح العميل فقط في
`SUPABASE_ANON_KEY`. لا تضع `service_role` أو مفتاحاً سرياً داخل Flutter.

## إعداد الويب

يمكن تمرير الإعدادات أثناء البناء:

```powershell
flutter build web --release --dart-define=SUPABASE_URL=https://example.supabase.co --dart-define=SUPABASE_ANON_KEY=<publishable-key>
```

أو استخدم `web/supabase_config.json` محلياً. هذا الملف مستبعد من Git ويجب ألا
يحتوي المستودع على مفاتيح سرية.

## الدفع التجريبي

- `ALLOW_PAYMENT_MOCK=true` يؤثر في Debug فقط.
- أي بناء Release أو بناء مع `PROD=true` يمنع بوابة المحاكاة.
- وجود `MOYASAR_PUBLISHABLE_KEY` ينقل التدفق إلى Moyasar.
- أسرار Moyasar وFirebase وSupabase توضع في Secrets الخاصة بالخادم أو Edge
	Functions، وليس في ملفات التطبيق.

## التحقق من الترخيص

خدمة `fal_backend` منفصلة وتستخدم Playwright للتحقق من بوابة REGA. شغّلها من
مجلدها عند الحاجة:

```powershell
cd fal_backend
npm install
npm start
```

## قاعدة البيانات

الترحيلات الرسمية موجودة في `supabase/migrations`. توجد ترحيلات موسومة
`dev_test` أو `grant_test` أو `reset` للاختبار المحلي فقط؛ راجع
`supabase/migrations/README.md` قبل تطبيقها على بيئة مشتركة.

## الاختبارات

اختبارات زر الإغلاق الموحد موجودة في
`test/app_page_close_button_test.dart`. زر `X` يستخدم `SafeOverlayPop` ويغلق
الطبقة الحالية أو يرجع إلى الصفحة السابقة دون إسقاط هيكل لوحة المستخدم.

قبل اعتبار النسخة جاهزة، يجب اختبار المسارات الحية يدوياً: التسجيل، رمز
التحقق، إنشاء إعلان، التراخيص، الدفع، الحجز، الإشعارات، والخروج.

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
