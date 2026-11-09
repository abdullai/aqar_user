# الجولة التعريفية (Onboarding Tour) - شرح كامل

## ✅ نعم، الجولة التعريفية صحيحة تماماً!

الجولة التعريفية يتم عرضها **عند الدخول لأول مرة** وتُعاد **من الإعدادات**، وهذا صحيح تماماً وفقاً للتصميم الحالي.

---

## 🏗️ البنية المعمارية

### 1. **ملفات إدارة الحالة (State Management)**

#### [lib/core/onboarding/device_first_run_prefs.dart](file:///D:/aqar_user/lib/core/onboarding/device_first_run_prefs.dart)
- **الدور الأساسي**: تخزين حالة الجولة والألوان بناءً على الجهاز والحساب
- **المفاتيح المستخدمة**:
  - `device_dashboard_tour_done_v1` - مفتاح الجهاز العام
  - `user_dashboard_tour_done_v1__<uid>` - مفتاح الحساب الفردي
  - `pending_dashboard_tour_replay_v1` - علم إعادة التشغيل من الإعدادات

**الدوال الرئيسية**:
```dart
isDashboardTourDone()           // التحقق من اكتمال الجولة
setDashboardTourDone()          // تسجيل اكتمال الجولة
requestDashboardTourReplay()    // طلب إعادة الجولة من الإعدادات
consumeReplayPending()          // استهلاك طلب الإعادة
clearTourAndAccentForReplay()   // مسح الجولة ولون التمييز للإعادة
```

#### [lib/core/onboarding/one_time_prompt_coordinator.dart](file:///D:/aqar_user/lib/core/onboarding/one_time_prompt_coordinator.dart)
- **الدور**: مركزية لإدارة الرسائل التي تُعرض **مرة واحدة فقط**
- **الترتيب الافتراضي**:
  1. `legal_terms_policy_coach_v2` - الشروط والأحكام
  2. `dashboard_onboarding_v3` - جولة لوحة التحكم
  3. `accent_color_prompt_v1` - اختيار لون التمييز

---

### 2. **واجهة الجولة (UI)**

#### [lib/widgets/dashboard_onboarding_overlay.dart](file:///D:/aqar_user/lib/widgets/dashboard_onboarding_overlay.dart)
- **الدور**: عرض الجولة كـ overlay على لوحة التحكم
- **الميزات**:
  - فقاعات شبه دائرية مع أسهم توضيحية
  - سهم يتحرك مع التبويب الحالي
  - تقدم تلقائي بعد 9 ثوان (قابل للتخصيص)
  - إغلاق بالضغط خارج الفقاعة

**البيانات**:
```dart
class DashboardOnboardingStepData {
  final String title;           // عنوان الخطوة
  final String body;            // وصف الخطوة
  final int? tabIndex;          // فهرس التبويب (أو null)
  final DashboardCoachArrow arrow;  // اتجاه السهم
  final double? navFraction;    // موضع السهم على الشريط السفلي
}
```

---

### 3. **التكامل مع لوحة التحكم**

#### [lib/screens/user_dashboard.ui.dart](file:///D:/aqar_user/lib/screens/user_dashboard.ui.dart) - الخطوط الرئيسية:

**عند التهيئة (initState)** - السطر 3500 تقريباً:
```
1. نقل المفاتيح القديمة إذا كانت موجودة
2. التحقق من `consumeReplayPending()` - هل طلب المستخدم إعادة الجولة من الإعدادات؟
3. إن كان نعم → مسح الجولة وعرضها مرة أخرى
4. إن كان لا → التحقق من اكتمال الجولة الأولى
5. إن لم تُكتمل → عرض الجولة
```

**عند الإغلاق** - السطر 3562:
```
1. تسجيل اكتمال الجولة
2. إذا كانت إعادة من الإعدادات → عرض اختيار الألوان
3. إعادة تعيين حالة `_showDashboardOnboarding`
```

---

### 4. **الإعدادات (Settings)**

#### [lib/screens/settings_page.dart](file:///D:/aqar_user/lib/screens/settings_page.dart) - السطر 3528:

**الزر**: "Replay dashboard tour" (الحساب والجولة التعريفية)

```dart
onTap: () async {
  await DeviceFirstRunPrefs.requestDashboardTourReplay();
  // عرض رسالة تأكيد
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t.settingsReplayDashboardTourSnackbar))
  );
  Navigator.of(context).maybePop();
}
```

---

## 📊 مسار التدفق (Flow Diagram)

```
┌─────────────────────────────────────────────────────────────────┐
│                    أول دخول للمستخدم                             │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
        isDashboardTourDone() == false?
                   │
         ┌─────────┴─────────┐
         │                   │
        نعم                   لا (عرض الجولة)
         │                   │
         │                   ▼
         │            ┌──────────────────┐
         │            │ DashboardOnboarding
         │            │     Overlay      │
         │            └────────┬─────────┘
         │                     │
         │                     ▼
         │            يُكمل المستخدم الجولة
         │                     │
         │                     ▼
         │            setDashboardTourDone()
         │                     │
         └─────────┬───────────┘
                   │
                   ▼
        ┌─────────────────────────────┐
        │   اختيار لون التمييز (اختياري) │
        └─────────────────────────────┘


┌──────────────────────────────────────────────────────┐
│   المستخدم يضغط "إعادة الجولة" من الإعدادات        │
└────────────────┬─────────────────────────────────────┘
                 │
                 ▼
      requestDashboardTourReplay()
      (يضع علم pending_dashboard_tour_replay_v1)
                 │
                 ▼
      Navigator.maybePop() -> dashboard
                 │
                 ▼
      consumeReplayPending() == true?
                 │
        ┌────────┴────────┐
        │                 │
       نعم                لا
        │                 │
        ▼                 │
clearTourAndAccentForReplay() │
        │                 │
        ▼                 ▼
_showDashboardOnboarding = true
_offerAccentAfterTourReplay = true
        │
        ▼
   عرض الجولة مرة أخرى
        │
        ▼
   عند الإغلاق → اختيار الألوان مرة أخرى
```

---

## 🌐 النصوص المترجمة

### اللغة الإنجليزية (English)
- **العنوان**: "Replay dashboard tour"
- **الوصف**: "Walks main tabs again (Home → My page → …). Starts when you return to the dashboard."
- **الرسالة**: (تظهر عند الضغط)

### اللغة العربية (Arabic)
- **العنوان**: "الحساب والجولة التعريفية"
- **الوصف**: "تمرّ على الرئيسية و«محفظتي» وغيرها خطوة بخطوة. تبدأ عند العودة للوحة التحكم."
- **الرسالة**: (تظهر عند الضغط)

---

## 🔄 حالات الاستخدام (Use Cases)

### 1️⃣ **أول دخول - مستخدم جديد**
- ✅ الجولة تظهر **تلقائياً** عند أول تحميل
- ✅ المستخدم يمكنه الضغط على الخطوات التالية أو انتظار 9 ثوان
- ✅ بعد الإغلاق → يُعرض اختيار لون التمييز

### 2️⃣ **المستخدم يطلب إعادة الجولة من الإعدادات**
- ✅ الضغط على "Replay dashboard tour"
- ✅ تُرجع الجولة مع علم الإعادة
- ✅ عند العودة للرئيسية → الجولة تظهر من جديد
- ✅ بعد الإغلاق → اختيار الألوان مرة أخرى (إن كان نعم في الإعادة)

### 3️⃣ **المستخدم يدخل بعد الجولة الأولى**
- ✅ **لا** جولة إذا أكملها من قبل (إلا إذا طلب الإعادة)
- ✅ الأداء محسّن لأن البيانات محفوظة محلياً

### 4️⃣ **حساب جديد على نفس الجهاز**
- ✅ **كل حساب يرى الجولة مرة** - المفاتيح مختلفة بـ UID
- ✅ لا تؤثر جولة حساب قديم على حساب جديد

---

## 🛠️ الملاحظات الفنية

### 1. **الترقية من الإصدارات القديمة**
```dart
migrateLegacyOnboardingKeysIfNeeded()
syncLegacyOneTimeIntoDeviceFlags()
```
- تمنع ظهور الجولة مرة أخرى للمستخدمين القدماء

### 2. **الأمان والخصوصية**
- المفاتيح مرتبطة بـ **UID المستخدم** عند الحسابات المسجلة
- المستخدمون الضيوف لهم مفاتيح جهاز عامة
- لا يُحفظ أي بيانات حساسة

### 3. **التوسعية**
```dart
OneTimePromptCoordinator.defaultPromptOrder = [
  'legal_terms_policy_coach_v2',    // الخطوة 1
  'dashboard_onboarding_v3',         // الخطوة 2
  'accent_color_prompt_v1',          // الخطوة 3
]
```
يمكن إضافة خطوات جديدة بسهولة دون تؤثير على القديمة

---

## ✨ الملخص

| الميزة | الحالة | الملاحظة |
|--------|--------|---------|
| **الجولة عند أول دخول** | ✅ عملة | تُعرض تلقائياً للمستخدمين الجدد |
| **الجولة من الإعدادات** | ✅ عملة | يمكن إعادتها من خيار "Replay tour" |
| **عدم تكرار الجولة** | ✅ عملة | تُعرض مرة واحدة فقط (إلا عند الطلب) |
| **دعم اللغات** | ✅ عملة | عربي وإنجليزي مدعوم كاملاً |
| **الأداء** | ✅ محسّن | البيانات محفوظة محلياً |
| **الحسابات المتعددة** | ✅ صحيح | كل حساب له جولة منفصلة |

---

## 📁 الملفات ذات الصلة

1. **الحالة**: [device_first_run_prefs.dart](file:///D:/aqar_user/lib/core/onboarding/device_first_run_prefs.dart)
2. **المنسق**: [one_time_prompt_coordinator.dart](file:///D:/aqar_user/lib/core/onboarding/one_time_prompt_coordinator.dart)
3. **الواجهة**: [dashboard_onboarding_overlay.dart](file:///D:/aqar_user/lib/widgets/dashboard_onboarding_overlay.dart)
4. **التطبيق**: [user_dashboard.ui.dart](file:///D:/aqar_user/lib/screens/user_dashboard.ui.dart) (خطوط 5159-5174)
5. **الإعدادات**: [settings_page.dart](file:///D:/aqar_user/lib/screens/settings_page.dart) (خطوط 3528-3545)
6. **الترجمات**: [app_localizations_*.dart](file:///D:/aqar_user/lib/l10n)

---

**آخر تحديث**: 2026-11-10
