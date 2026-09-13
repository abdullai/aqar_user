// lib/core/config/app_config.dart
//
// Single entry point for global layout + brand constants. Runtime theme / locale
// still use [themeModeNotifier], [langNotifier], and [accentSeedNotifier] in
// `main.dart` (loaded from SharedPreferences at startup).

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../shared/core/supabase_runtime_overrides.dart';
import '../theme/app_accent.dart';

/// App-wide constants (English identifiers; UI strings stay in l10n).
abstract final class AppConfig {
  /// Centered shell max width on web & desktop native builds.
  static const double maxContentWidth = 800;

  // ---------------------------------------------------------------------------
  // SharedPreferences keys — single source (language, theme, session, unlock)
  // ---------------------------------------------------------------------------
  static const String prefLangKey = 'app_lang';
  static const String prefThemeKey = 'app_theme';
  static const String prefHapticsEnabledKey = 'haptics_enabled';
  static const String prefTextScaleKey = 'app_text_scale_factor';
  static const String prefGuestModeKey = 'guest_mode';
  static const String prefEntryModeKey = 'entry_mode';

  /// مفاتيح قديمة — تُزال عند تسجيل الخروج أو الدخول كمستخدم (كان بعض الشاشات تكتبها بجانب [prefGuestModeKey]).
  static const String prefGuestLegacyIsGuestKey = 'is_guest';
  static const String prefGuestLegacyGuestKey = 'guest';
  static const String prefFastLoginEnabledKey = 'fast_login_enabled';
  static const String prefFastLoginPinSetKey = 'fast_login_pin_set';
  static const String prefAppPausedAtMsKey = 'app_paused_at_ms';
  static const String prefBgLockGraceMinutesKey = 'app_bg_lock_grace_minutes';

  /// مفتاح مدينة الاستكشاف الافتراضي في الرئيسية (مفتاح من saudi_locations.json أو `all`).
  static const String prefPreferredExploreCityKey = 'preferred_explore_city_v1';

  /// نص العرض (محافظة — مدينة) بعد الاختيار من الخريطة أو التسلسل الهرمي.
  static const String prefPreferredExploreDisplayKey =
      'preferred_explore_display_v1';

  /// إحداثيات آخر اختيار من الخريطة/الهرمية (لترتيب «الأقرب» في الرئيسية).
  static const String prefPreferredExploreLatKey = 'preferred_explore_lat_v1';
  static const String prefPreferredExploreLngKey = 'preferred_explore_lng_v1';

  /// مسودة لوحة «بحث متقدم» (حفظ ديناميكي أثناء تعديل الورقة السفلية).
  static const String prefDashboardAdvancedSearchDraftKey =
      'dashboard_adv_search_draft_v1';

  /// موافقة المستخدم على الكوكيز/التخزين المحلي الضروري للتشغيل (مع الشروط عند أول دخول).
  static const String prefRegulatoryCookieAckKey = 'regulatory_cookie_ack_v1';

  /// آخر نشاط لجلسة الضيف على الويب (انظر web_session_ttl.dart).
  static const String prefWebGuestLastActivityMs =
      'web_guest_last_activity_ms';

  /// عرض تواريخ الإعلانات/الطلبات: device | utc_plus_3 | utc_plus_4 | utc
  static const String prefListingDateZoneKey = 'listing_date_display_zone_v1';

  /// Combined with system text scale in [buildAppCombinedTextScaler].
  static const double textScaleMin = 0.85;
  static const double textScaleMax = 1.40;

  /// Minimum tap target (Material 3 / accessibility).
  static const double minInteractiveTarget = 48;

  /// Primary accent palette size (Material seeds).
  static const int primaryAccentCount = AppAccent.count;

  static List<Color> get primaryAccentPalette => AppAccent.seeds;

  static Color accentSeedAt(int index) =>
      AppAccent.seedForIndex(index.clamp(0, AppAccent.count - 1));

  /// مفتاح Maps JavaScript — من `--dart-define` أو dotenv أو `supabase_config.json`.
  /// قيّده في Google Cloud (HTTP referrer / Android SHA / iOS bundle). لا قيمة افتراضية في الكود.
  static String get googleMapsWebBrowserKey {
    const fromDefine = String.fromEnvironment(
      'GOOGLE_MAPS_WEB_KEY',
      defaultValue: '',
    );
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    final fromWeb = (SupabaseRuntimeOverrides.webGoogleMapsKey ?? '').trim();
    if (fromWeb.isNotEmpty) return fromWeb;
    return (dotenv.env['GOOGLE_MAPS_WEB_KEY'] ?? '').trim();
  }

  /// عند `true`: زر «نشر الإعلان» يظهر في تبويب التصريح حتى في مرحلة `permit_pending` دون تصريح.
  /// في الإنتاج يُفضّل `false` حتى يُكمَل رفع/ربط التصريح قبل النشر.
  static const bool allowMarketingPublishWithoutPermit = false;

  // ===========================================================================
  // ⚠️ علامتا التطوير — لا تتركهما `true` في الإنتاج.
  // ===========================================================================

  /// زر «تفعيل اشتراك تطوير 365 يوم» يظهر في paywall (يستدعي RPC
  /// `dev_grant_test_subscription_for_me`) + يظهر للمستخدم الحالي فقط.
  ///
  /// • `true`  → أثناء التطوير لتفعيل اشتراك تجريبي بنقرة من الـ paywall.
  /// • `false` → في **الإنتاج** (يختفي الزر تماماً، حتى لو ضغط مهاجم لن يتم).
  ///
  /// في DEBUG يُفعَّل تلقائياً عبر `kDebugMode`، لذا يمكنك تركها `false` للإنتاج
  /// مع الإبقاء على ظهور الزر للمطوّر الذي يُشغّل من Flutter DevTools.
  static const bool allowDevTestSubscriptionGrant = false;

  /// تجاوز فحص الاشتراك المدفوع — كل بوابات الـ paywall تُفتح بدون اشتراك.
  ///
  /// • `true`  → فقط في **التطوير الكامل** (تخطّي كل القيود لاختبار الواجهات).
  /// • `false` → في **الإنتاج** + أثناء اختبار سير العمل الحقيقي حتى يعمل
  ///             paywall بشكل طبيعي. (يبقى زر «تجربة 3 أيام» مفعّلاً لأنه RPC
  ///             حقيقي يكتب في قاعدة البيانات.)
  ///
  /// **يجب أن تكون `false` قبل النشر النهائي.**
  static const bool devBypassSubscriptionGate = false;
}

/// Responsive shell / navigation breakpoints.
abstract final class AppLayout {
  /// لا نضيّق التطبيق بالكامل: النماذج تقيّد نفسها، واللوحة تستخدم عرض الشاشة.
  static bool shouldConstrainAppShell(BuildContext context) => false;

  /// Bottom [NavigationBar] on all platforms (phones, web, desktop native).
  static bool useDashboardSideNavigation(BuildContext context) {
    return false;
  }
}
