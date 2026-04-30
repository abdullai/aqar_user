// lib/core/config/app_config.dart
//
// Single entry point for global layout + brand constants. Runtime theme / locale
// still use [themeModeNotifier], [langNotifier], and [accentSeedNotifier] in
// `main.dart` (loaded from SharedPreferences at startup).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  /// نفس المفتاح المستخدم في `web/index.html` لـ Maps JavaScript API.
  /// يُستعمل لصورة خريطة ثابتة على الويب عند فشل DNS لخوادم OSM الأخرى.
  static const String googleMapsWebBrowserKey =
      'AIzaSyB1GB51H6O-8O5wab9WnEDSj5aY_qQL4Vs';
}

/// Responsive shell / navigation breakpoints.
abstract final class AppLayout {
  static bool _isHandheldNative() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Narrow phone/tablet native: full-width content. Desktop native: centered column.
  /// Web: full viewport width (RTL rail + lists); avoids a narrow centered column.
  static bool shouldConstrainAppShell(BuildContext context) {
    if (_isHandheldNative()) return false;
    if (kIsWeb) return false;
    return true;
  }

  /// Keep bottom [NavigationBar] on web; side rail only on wide desktop (Windows/macOS/Linux).
  static bool useDashboardSideNavigation(BuildContext context) {
    if (_isHandheldNative()) return false;
    if (kIsWeb) return false;
    final w = MediaQuery.sizeOf(context).width;
    return w >= 880;
  }
}
