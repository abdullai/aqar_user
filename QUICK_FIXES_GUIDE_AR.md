# دليل الإصلاحات السريعة - صفحة إضافة العقار

## 1️⃣ إصلاح الأزرار فوق لوحة المفاتيح (الأولوية العالية)

### الحالية (خاطئة):
```dart
// السطر 6120
Material(
  elevation: 8,
  color: cs.surface,
  shadowColor: Colors.black26,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: LayoutBuilder(
      builder: (context, c) {
        // الأزرار هنا
      },
    ),
  ),
)
```

### الحل المقترح:
استبدل المقطع أعلاه بـ:

```dart
Padding(
  padding: MediaQuery.of(context).viewInsets.bottom > 0
      ? EdgeInsets.fromLTRB(12, 10, 12, 
          10 + MediaQuery.of(context).viewInsets.bottom)
      : const EdgeInsets.fromLTRB(12, 10, 12, 10),
  child: Material(
    elevation: 8,
    color: cs.surface,
    shadowColor: Colors.black26,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, c) {
          // الأزرار هنا
        },
      ),
    ),
  ),
)
```

**التوضيح:** عند ظهور لوحة المفاتيح، يُرفع الـ Material widget تلقائياً بمقدار ارتفاع لوحة المفاتيح.

---

## 2️⃣ تحسين التمرير بين الحقول

### المشكلة:
عند الانتقال للخطوة التالية، الحقل الأول قد لا يكون مرئياً على الشاشات الصغيرة.

### الحل:
أضف في `initState`:

```dart
final Map<int, FocusNode> _stepFocusNodes = {
  0: FocusNode(),
  1: FocusNode(),
  2: FocusNode(),
  3: FocusNode(),
  4: FocusNode(),
  5: FocusNode(),
};
```

ثم عدّل `_wizardNext`:

```dart
void _wizardNext() async {
  final pane = _wizardPaneKind(_wizardStep);
  if (!_validateWizardStep(_wizardStep)) return;
  if (_wizardStep < _kWizardLastStep) {
    setState(() => _wizardStep++);
    
    // ارفع الصفحة للأعلى
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WizardStepNavigation.scrollToTop(_scrollCtrl);
      // ركّز على الحقل الأول من الخطوة الجديدة
      if (_wizardStep < 6) {
        _stepFocusNodes[_wizardStep]?.requestFocus();
      }
    });
  }
}
```

---

## 3️⃣ إصلاح الشاشات الصغيرة (تخطيط الأزرار)

### الحالية (السطر 6155):
```dart
if (narrow) { // narrow = c.maxWidth < 520
  return Column(...);
}
```

### الحل المحسّن:
```dart
if (narrow) { // narrow = c.maxWidth < 600
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      nextBtn,
      const SizedBox(height: 8),
      backBtn,
    ],
  );
}
```

**تغييرات:**
- غيّر `520` إلى `600` (أفضل للهواتف القديمة)
- أضف `crossAxisAlignment: CrossAxisAlignment.stretch` للأزرار
- أضف padding إضافي عند الضيق

---

## 4️⃣ تشفير بيانات المسودة (أمان)

### الحالية (غير آمنة):
```dart
// السطر 800
await WizardFormDraft.save(
  namespace: _draftNamespace,
  userId: uid,
  data: _snapshotListingDraft(),
);
```

### الحل:
أضف هذا الحزم في `pubspec.yaml`:
```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
  encrypt: ^5.0.0
```

ثم عدّل الحفظ:
```dart
Future<void> _persistListingDraft({bool showSnack = true}) async {
  final uid = _sb.auth.currentUser?.id ?? '';
  if (uid.isEmpty) return;
  
  final data = _snapshotListingDraft();
  final jsonString = jsonEncode(data);
  
  // تشفير البيانات
  final storage = const FlutterSecureStorage();
  await storage.write(
    key: 'listing_draft_${uid}',
    value: jsonString,
  );
  
  if (showSnack && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isAr ? 'حُفظت المسودة بأمان' : 'Draft saved securely')),
    );
  }
}
```

---

## 5️⃣ التحقق الإلزامي من رخصة الفال

### المشكلة:
الرخصة تُتحقق بـ debounce، قد لا تكتمل قبل النشر.

### الحل:
في `_submit()` قبل الحفظ، أضف:

```dart
Future<void> _submit() async {
  if (_saving || _publishLock) return;
  
  // ... الفحوصات الأخرى ...
  
  // التحقق الإلزامي من الرخصة
  if (_adLicenseSource == _AdLicenseSource.inApp) {
    if (!(_regaVerifyOk == true)) {
      setState(() => _error = _isAr
          ? 'يجب التحقق من رخصة الفال أولاً.'
          : 'Please verify your FAL license first.');
      return;
    }
  }
  
  // ... باقي الحفظ ...
}
```

---

## 6️⃣ التحقق من صحة الإحداثيات

### أضف هذه الدالة:
```dart
bool _validateCoordinates() {
  if (_lat == null || _lng == null) return true; // اختياري
  
  // حدود السعودية
  const double minLat = 16.0;
  const double maxLat = 32.5;
  const double minLng = 32.0;
  const double maxLng = 56.0;
  
  if (_lat! < minLat || _lat! > maxLat || 
      _lng! < minLng || _lng! > maxLng) {
    setState(() => _error = _isAr
        ? 'الإحداثيات خارج حدود المملكة العربية السعودية.'
        : 'Coordinates are outside Saudi Arabia.');
    return false;
  }
  return true;
}
```

ثم استدعها في `_submit()`:
```dart
if (!_validateCoordinates()) return;
```

---

## 7️⃣ تنقية مدخلات النصوص

### أضف في الأعلى:
```dart
import 'package:html_unescape/html_unescape.dart';
import 'package:html/parser.dart' show parse;

String _sanitizeInput(String input) {
  // إزالة أي HTML tags
  var document = parse(input);
  String parsedString = parse(document.body?.text).documentElement?.text ?? '';
  return parsedString;
}
```

ثم في `_submit()` قبل الحفظ:
```dart
final cleanTitle = _sanitizeInput(_title.text);
final cleanDesc = _sanitizeInput(_desc.text);
```

---

## 8️⃣ إضافة حفظ تلقائي

### أضف في `initState`:
```dart
Timer? _autoSaveTimer;

@override
void initState() {
  super.initState();
  // ... الكود الحالي ...
  
  // حفظ تلقائي كل 5 دقائق
  _autoSaveTimer = Timer.periodic(Duration(minutes: 5), (_) async {
    if (_hasUnsavedWizardInput() && !_saving) {
      await _persistListingDraft(showSnack: false);
    }
  });
}

@override
void dispose() {
  _autoSaveTimer?.cancel();
  // ... الكود الحالي ...
  super.dispose();
}
```

---

## 9️⃣ تحسين معالجة الأخطاء للشاشات الصغيرة

### عدّل `_ErrorBox`:
```dart
if (_error != null) {
  _scrollToError();
  _ErrorBox(
    text: _error!,
    isAr: _isAr,
    // أضف animation
    key: ValueKey(_error),
  );
}

void _scrollToError() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
  });
}
```

---

## 🔟 ميزة ذكية: تنبيه من الأسعار الشاذة

### أضف هذه الدالة:
```dart
Future<void> _checkPriceAnomaly() async {
  final price = _parseDouble(_price.text);
  if (price <= 0) return;
  
  try {
    final indicators = RegaOpenIndicatorsService.instance;
    // تحقق من متوسط السعر للمنطقة والنوع
    final avgPrice = await indicators.getAveragePrice(
      city: _city.text,
      type: _type,
    );
    
    if (avgPrice != null && avgPrice > 0) {
      final ratio = price / avgPrice;
      if (ratio > 1.5 || ratio < 0.5) {
        setState(() => _error = _isAr
            ? 'السعر قد يكون شاذاً (أعلى/أقل من المتوسط بـ ${(ratio * 100).toStringAsFixed(0)}%)'
            : 'Price seems unusual (${(ratio * 100).toStringAsFixed(0)}% of average)');
      }
    }
  } catch (_) {}
}
```

استدعها عند تغيير السعر:
```dart
_price.addListener(() {
  _onPriceOrAreaChanged();
  unawaited(_checkPriceAnomaly());
});
```

---

## ملاحظات مهمة:

✅ كل التغييرات أعلاه **متوافقة** مع البنية الحالية
✅ لا تحتاج إلى إعادة هندسة كاملة
✅ يمكن تطبيقها تدريجياً
⚠️ اختبر على الأجهزة الصغيرة (< 5 inches)
⚠️ اختبر في الوضع الرأسي والأفقي

---

**وقت التطبيق المقدّر:** 4-6 ساعات للإصلاحات الأساسية
**وقت الاختبار:** 2-3 ساعات

