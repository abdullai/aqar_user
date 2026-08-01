import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../share/app_listing_links.dart';

/// أسماء العلامة والسجل التجاري — مصدر واحد للحقيقة.
/// Smart brand naming: native app vs web/browser (incl. mobile web & Windows).
abstract final class AppBranding {
  // ---------------------------------------------------------------------------
  // الأسماء الرسمية — Saudi commercial registration / legal display
  // ---------------------------------------------------------------------------
  static const String companyNameAr = 'مؤسسة موثوق لاين العقارية';
  static const String companyNameEn =
      'Mawthuq Line Real Estate Establishment';

  /// اسم التطبيق في المتاجر (App Store / Google Play) والتطبيق الأصلي.
  static const String appStoreNameAr = 'تطبيق موثوق لاين العقاري';
  static const String appStoreNameEn = 'Mawthuq Line Real Estate App';

  /// العلامة التجارية (شعارات، عناوين فرعية، SEO).
  static const String brandNameAr = 'موثوق لاين العقارية';
  static const String brandNameEn = 'Mawthuq Line Real Estate';

  static const String shortNameAr = 'موثوق لاين';
  static const String shortNameEn = 'Mawthuq Line';

  static const String websiteUrl = 'https://eaqar-mawthuq.web.app';
  static const String supportEmail = 'support@mawthuq-line.com';
  static const String supportPhone = '+966500229909';

  /// يُحدَّث برقم السجل التجاري الموحّد الفعلي عند توفره.
  static const String? commercialRegisterNumber = null;

  // ---------------------------------------------------------------------------
  // بيئة التشغيل
  // ---------------------------------------------------------------------------

  /// ويب / متصفح (جوال أو سطح مكتب) / ويندوز / ماك / لينكس → اسم المؤسسة القانوني.
  /// تطبيق أصلي (Android/iOS فقط) → اسم التطبيق في المتاجر.
  static bool get usesEstablishmentDisplayName {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @Deprecated('Use usesEstablishmentDisplayName')
  static bool get isWebExperience => usesEstablishmentDisplayName;

  static bool get isNativeMobileApp {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ---------------------------------------------------------------------------
  // صور العلامة — ويب/متصفحات → logo.png | تطبيق المتاجر → splashscreen.png
  // ---------------------------------------------------------------------------

  /// شعار المؤسسة — ويب، متصفح ويندوز/جوال، سطح المكتب.
  static const String establishmentLogoAsset = 'assets/logo.png';

  /// شعار التطبيق — Android/iOS من المتاجر (نفس شاشة البداية).
  static const String nativeAppLogoAsset = 'assets/splashscreen.png';

  /// أيقونة المتجر / launcher (ثابتة — لا تتبدّل حسب السياق).
  static const String storeLauncherIconAsset = 'assets/logoe.png';

  /// هاتف / ويب جوال / شاشة ضيّقة → صورة واسم التطبيق.
  /// آيباد / ويب ويندوز عريض / سطح مكتب → صورة واسم المؤسسة.
  static bool prefersAppVisuals([BuildContext? context]) {
    if (context != null) {
      final size = MediaQuery.sizeOf(context);
      // shortestSide < 600 ≈ هاتف؛ الآيباد واللوحي ≥ 600.
      final phoneLike = size.shortestSide < 600;
      if (isNativeMobileApp) return phoneLike;
      if (kIsWeb) {
        // متصفح جوال أو نافذة ضيّقة → تطبيق؛ ويندوز/آيباد عريض → مؤسسة.
        return phoneLike || size.width < 700;
      }
      return false;
    }
    return isNativeMobileApp;
  }

  /// شاشة كبيرة على ويب سطح المكتب (ويندوز/ماك/لينكس) — نص Caps Lock بدل السهم.
  static bool isLargeDesktopWeb(BuildContext context) {
    if (!kIsWeb) return false;
    final desktopOs = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!desktopOs) return false;
    return MediaQuery.sizeOf(context).width >= 700;
  }

  /// الصورة الرئيسية حسب بيئة التشغيل (مصدر واحد للحقيقة).
  static String get primaryLogoAsset =>
      isNativeMobileApp ? nativeAppLogoAsset : establishmentLogoAsset;

  /// شعار الإقلاع/التمهيد حسب حجم الشاشة (ويب جوال ≠ ويب ويندوز).
  static String bootLogoAsset(BuildContext context) =>
      prefersAppVisuals(context) ? nativeAppLogoAsset : establishmentLogoAsset;

  /// اسم العرض حسب البيئة والحجم.
  static String displayNameForContext(BuildContext context, {required bool isAr}) {
    if (prefersAppVisuals(context)) {
      return isAr ? appStoreNameAr : appStoreNameEn;
    }
    return isAr ? companyNameAr : companyNameEn;
  }

  /// عنوان الترحيب في شاشة الدخول حسب الحجم/المنصة.
  static String welcomeHeadline(BuildContext context, {required bool isAr}) {
    if (prefersAppVisuals(context)) {
      return isAr
          ? 'مرحبا بكم في تطبيق موثوق لاين العقاري'
          : 'Welcome to Mawthuq Line Real Estate App';
    }
    return isAr ? companyNameAr : companyNameEn;
  }

  /// بديل الإعلان/الطلب عند غياب صورة المستخدم.
  static String get listingPlaceholderAsset => primaryLogoAsset;

  /// قيمة مرجعية في قاعدة البيانات — الغلاف الذكي (لا ملف تخزين حقيقي).
  static const String smartDefaultCoverStorageSentinel = '__smart_branding_cover__';

  /// معاينة مشاركة الويب للغلاف الذكي (مؤسسة).
  static String webEstablishmentCoverShareUrl() =>
      '${AppListingLinks.webOrigin}/assets/assets/logo.png';

  /// معاينة مشاركة الويب للغلاف الذكي (تطبيق — عند الحاجة لرابط HTTP).
  static String webNativeAppCoverShareUrl() =>
      '${AppListingLinks.webOrigin}/assets/assets/splashscreen.png';
  static String displayName({required bool isAr}) {
    if (usesEstablishmentDisplayName) {
      return isAr ? companyNameAr : companyNameEn;
    }
    return isAr ? appStoreNameAr : appStoreNameEn;
  }

  /// الاسم القانوني — ثابت في الفواتير والعقود والإشعارات الرسمية.
  static String legalName({required bool isAr}) =>
      isAr ? companyNameAr : companyNameEn;

  static String brandName({required bool isAr}) =>
      isAr ? brandNameAr : brandNameEn;

  static String shortName({required bool isAr}) =>
      isAr ? shortNameAr : shortNameEn;

  static String appName({required bool isAr}) =>
      isAr ? appStoreNameAr : appStoreNameEn;

  /// سطر حقوق النشر.
  static String copyrightLine({required bool isAr}) => isAr
      ? '© جميع الحقوق محفوظة — $companyNameAr'
      : '© All rights reserved — $companyNameEn';

  /// سطر قانوني مع السجل التجاري إن وُجد.
  static String legalNoticeLine({required bool isAr}) {
    final base = legalName(isAr: isAr);
    final cr = commercialRegisterNumber?.trim();
    if (cr == null || cr.isEmpty) return base;
    return isAr ? '$base — السجل التجاري $cr' : '$base — CR $cr';
  }

  /// وصف قصير للمنصة.
  static String tagline({required bool isAr}) {
    if (usesEstablishmentDisplayName) {
      return isAr
          ? 'منصة عقارية سعودية موثوقة'
          : 'Trusted Saudi real estate platform';
    }
    return isAr
        ? 'تطبيق عقاري سعودي موثوق'
        : 'Trusted Saudi real estate app';
  }

  static String taglineForContext(BuildContext context, {required bool isAr}) {
    if (prefersAppVisuals(context)) {
      return isAr
          ? 'تطبيق عقاري سعودي موثوق'
          : 'Trusted Saudi real estate app';
    }
    return isAr
        ? 'منصة عقارية سعودية موثوقة'
        : 'Trusted Saudi real estate platform';
  }

  /// عنوان SEO للويب.
  static String metaTitle({required bool isAr}) {
    if (usesEstablishmentDisplayName) {
      return isAr
          ? '$companyNameAr — منصة عقارية سعودية موثوقة'
          : '$companyNameEn — Trusted Saudi Real Estate Platform';
    }
    return isAr
        ? '$appStoreNameAr — منصة عقارية سعودية موثوقة'
        : '$appStoreNameEn — Trusted Saudi Real Estate Platform';
  }

  static String metaDescription({required bool isAr}) => isAr
      ? 'منصة عقارية سعودية موثوقة لتداول العقارات بسهولة وأمان — $companyNameAr'
      : 'A trusted Saudi real estate platform — $companyNameEn';

  static String copyrightBilingual() =>
      '© $companyNameAr | $companyNameEn';

  /// تسمية الشريك في الفواتير والتصدير (بدلاً من «العميل»).
  static String invoicePartnerLabel({required bool isAr}) =>
      isAr ? 'شريكنا العقاري' : 'Real estate partner';

  static String invoicePartnerSectionTitle({required bool isAr}) =>
      isAr ? 'بيانات شريكنا العقاري' : 'Real estate partner details';

  static String shareBrandLine({required bool isAr}) => isAr
      ? '$brandNameAr — $brandNameEn'
      : '$brandNameEn — $brandNameAr';

  // ---------------------------------------------------------------------------
  // أحجام متجاوبة — تصغير/تكبير بدون التفاف على الجوال
  // ---------------------------------------------------------------------------

  static double logoSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 48;
    if (w < 480) return 56;
    if (w < 600) return 64;
    if (w < 900) return 72;
    if (w < 1200) return 88;
    return 104;
  }

  /// شعار بارز في شاشة تسجيل الدخول — واضح وكبير حسب الشاشة.
  static double loginHeroLogoSize(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final w = mq.width;
    final h = mq.height;
    final compactH = h < 700;
    if (w < 360) return compactH ? 148.0 : 172.0;
    if (w < 480) return compactH ? 160.0 : 188.0;
    if (w < 600) return compactH ? 152.0 : 176.0;
    if (w < 900) return compactH ? 140.0 : 160.0;
    if (w < 1200) return 128.0;
    return 140.0;
  }

  static double titleFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 15;
    if (w < 480) return 17;
    if (w < 600) return 19;
    if (w < 900) return 22;
    if (w < 1200) return 26;
    return 30;
  }

  static double subtitleFontSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 480) return 11;
    if (w < 900) return 12;
    return 14;
  }

  static bool isCompactWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  /// تطبيع نص معروض للمستخدم (من DB أو push أو قوالب قديمة).
  static String normalizeUserFacing(
    String? input, {
    required bool isAr,
  }) {
    final t = (input ?? '').trim();
    if (t.isEmpty) return t;
    return migrateLegacyText(t);
  }

  /// اسم باقة اشتراك من صف قاعدة البيانات.
  static String planNameFromRow(
    Map<String, dynamic> plan, {
    required bool isAr,
  }) {
    final raw = isAr
        ? '${plan['name_ar'] ?? plan['name_en'] ?? ''}'
        : '${plan['name_en'] ?? plan['name_ar'] ?? ''}';
    return normalizeUserFacing(raw, isAr: isAr);
  }

  /// عنوان معاملة فوترة من صف قاعدة البيانات.
  static String billingTitleFromRow(
    Map<String, dynamic> row, {
    required bool isAr,
  }) {
    final raw = isAr
        ? '${row['title_ar'] ?? row['title_en'] ?? '—'}'
        : '${row['title_en'] ?? row['title_ar'] ?? '—'}';
    return _localizeBillingTitlePeriod(normalizeUserFacing(raw, isAr: isAr), isAr: isAr);
  }

  /// ترجمة فترة الفوترة في العنوان (monthly → شهري).
  static String billingPeriodLabel(String period, {required bool isAr}) {
    final p = period.trim().toLowerCase().replaceAll(' ', '_');
    switch (p) {
      case 'monthly':
        return isAr ? 'شهري' : 'Monthly';
      case 'yearly':
      case 'annual':
        return isAr ? 'سنوي' : 'Yearly';
      case 'lifetime_one_time':
      case 'one_time':
        return isAr ? 'مرة واحدة' : 'One-time';
      default:
        return period;
    }
  }

  static String billingTitleForCheckout({
    required String planLabel,
    required String period,
    required bool isAr,
  }) {
    final cleaned = _cleanBillingPlanLabel(planLabel, isAr: isAr);
    if (_planLabelAlreadyIncludesPeriod(cleaned, period, isAr: isAr)) {
      return cleaned;
    }
    return '$cleaned — ${billingPeriodLabel(period, isAr: isAr)}';
  }

  /// عنوان فاتورة/إيصال نظيف بدون تكرار «شهري — شهري».
  static String billingDisplayTitle({
    required String rawTitle,
    required bool isAr,
    String? periodHint,
  }) {
    var t = normalizeUserFacing(rawTitle, isAr: isAr).trim();
    if (t.isEmpty || t == '—') return t;

    t = t.replaceAll(RegExp(r'\s*[-–—]\s*'), ' — ');
    final parts = t.split(' — ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return t;

    final deduped = <String>[];
    for (final part in parts) {
      final lower = part.toLowerCase();
      final isDup = deduped.any((prev) {
        final pl = prev.toLowerCase();
        return pl == lower ||
            (pl.contains(lower) && lower.length >= 4) ||
            (lower.contains(pl) && pl.length >= 4);
      });
      if (!isDup) deduped.add(part);
    }

    var plan = deduped.first;
    plan = _cleanBillingPlanLabel(plan, isAr: isAr);

    if (deduped.length == 1) {
      if (periodHint != null &&
          periodHint.trim().isNotEmpty &&
          !_planLabelAlreadyIncludesPeriod(plan, periodHint, isAr: isAr)) {
        return '$plan — ${billingPeriodLabel(periodHint, isAr: isAr)}';
      }
      return plan;
    }

    final tail = deduped.sublist(1).join(' · ');
    if (_planLabelAlreadyIncludesPeriod(plan, tail, isAr: isAr) ||
        _planLabelAlreadyIncludesPeriod(plan, periodHint ?? '', isAr: isAr)) {
      return plan;
    }
    return '$plan — $tail';
  }

  static String _cleanBillingPlanLabel(String label, {required bool isAr}) {
    var s = label.trim();
    s = s.replaceAllMapped(
      RegExp(r'\(\s*(\d+)\s*طلب\s*/\s*شهري\s*\)', caseSensitive: false),
      (m) => isAr ? '(${m[1]} طلب/شهر)' : '(${m[1]} req/mo)',
    );
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    return s.trim();
  }

  static bool _planLabelAlreadyIncludesPeriod(
    String label,
    String period, {
    required bool isAr,
  }) {
    if (label.trim().isEmpty) return false;
    final l = label.toLowerCase();
    final p = period.trim().toLowerCase().replaceAll(' ', '_');
    switch (p) {
      case 'monthly':
        return l.contains('شهري') ||
            l.contains('monthly') ||
            l.contains('/شهر') ||
            l.contains('/mo') ||
            l.contains('per month');
      case 'yearly':
      case 'annual':
        return l.contains('سنوي') ||
            l.contains('yearly') ||
            l.contains('annual') ||
            l.contains('/year');
      case 'lifetime_one_time':
      case 'one_time':
        return l.contains('مرة واحدة') ||
            l.contains('one-time') ||
            l.contains('one time') ||
            l.contains('lifetime');
      default:
        if (p.isEmpty) return false;
        final localized = billingPeriodLabel(period, isAr: isAr).toLowerCase();
        return l.contains(localized);
    }
  }

  static String _localizeBillingTitlePeriod(String title, {required bool isAr}) {
    return billingDisplayTitle(rawTitle: title, isAr: isAr);
  }

  /// استبدال أسماء قديمة في نصوص ثابتة (هجرة تدريجية + عرض DB).
  static String migrateLegacyText(String input) {
    var s = input;
    // الأطول أولاً لتجنب استبدال جزئي خاطئ.
    const pairs = <List<String>>[
      ['منصة موثوق العقاري الإلكترونية', companyNameAr],
      ['منصة عقار موثوق', companyNameAr],
      ['تطبيق موثوق العقاري', appStoreNameAr],
      ['تطبيق موثوق لاين العقاري', appStoreNameAr],
      ['عقار موثوق', brandNameAr],
      ['موثوق العقاري', brandNameAr],
      ['Aqar Mawthuq Real Estate', companyNameEn],
      ['Aqar Mawthuq', brandNameEn],
      ['Aqar Reliable', brandNameEn],
      ['Motawoq Real Estate', brandNameEn],
      ['Trusted Aqar', brandNameEn],
      ['Motawoq', shortNameEn],
      ['Mawthuq', shortNameEn],
    ];
    for (final p in pairs) {
      s = s.replaceAll(p[0], p[1]);
    }
    return s;
  }
}
