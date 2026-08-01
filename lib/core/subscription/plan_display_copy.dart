import '../../services/subscription_service.dart';

/// نصوص عرض الباقات — مصدر واحد يقرأ حقول قاعدة البيانات (name/description/limits/features).
class PlanDisplayCopy {
  PlanDisplayCopy._();

  static bool _isAr(String lang) => lang.toLowerCase() != 'en';

  static int? _intOf(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static double _autoPayPct(Map<String, dynamic> plan) {
    final v = plan['auto_pay_discount_percent'];
    if (v is num && v > 0) return v.toDouble();
    return 10.0;
  }

  static String _lim(dynamic v, {required bool isAr}) {
    final n = _intOf(v);
    if (n == null || n <= 0) return isAr ? 'غير محدود' : 'Unlimited';
    return '$n';
  }

  static String _descriptionFromDb(Map<String, dynamic> plan, {required bool isAr}) {
    final key = isAr ? 'description_ar' : 'description_en';
    final alt = isAr ? 'description_en' : 'description_ar';
    for (final k in [key, alt]) {
      final s = (plan[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _featureTextFromJson(
    Map<String, dynamic> plan, {
    required bool isAr,
    required String jsonKey,
  }) {
    final raw = plan['features'];
    if (raw is! Map) return '';
    final m = Map<String, dynamic>.from(raw);
    final key = isAr ? '${jsonKey}_ar' : '${jsonKey}_en';
    final alt = isAr ? '${jsonKey}_en' : '${jsonKey}_ar';
    for (final k in [key, alt, jsonKey]) {
      final s = (m[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// فقرة «عن الباقة» — من description_* أو من بيانات الباقة.
  static String aboutParagraph(
    Map<String, dynamic> plan, {
    required String lang,
    required String planName,
  }) {
    final isAr = _isAr(lang);
    final fromDb = _descriptionFromDb(plan, isAr: isAr);
    if (fromDb.isNotEmpty) return fromDb;

    final order = _intOf(plan['sort_order']) ?? 0;
    final isTrial = plan['is_trial_plan'] == true;
    final program =
        (plan['plan_program'] ?? 'monthly').toString().trim().toLowerCase();

    if (isTrial) {
      return isAr
          ? 'باقة تجريبية لمرة واحدة لكل مستخدم — تمنحك تجربة عملية لميزات المنصة قبل الاشتراك المدفوع.'
          : 'A one-time trial per user to explore platform features before a paid subscription.';
    }
    if (program == 'lifetime_one_time' || order == 11 || order == 12 || order == 13) {
      return isAr
          ? 'باقة «عروض السوق» — رصيد محدود لإتمام الصفقات على طلبات السوق من الرئيسية. لا تجديد تلقائي؛ ينتهي الرصيد عند استنفاده.'
          : 'Market Offers plan — a fixed balance to complete deals on home market requests. No auto-renewal; balance ends when used up.';
    }
    if (SubscriptionService.isComprehensivePlanSortOrder(order)) {
      return isAr
          ? 'باقة $planName — ترقية شاملة بحصة «إتمام صفقة» أعلى من الباقة الأساسية؛ تُفعَّل فور الدفع.'
          : '$planName — comprehensive upgrade with a higher «Complete deal» quota; activates immediately after payment.';
    }
    if (order == 1) {
      return isAr
          ? 'باقة $planName — حساب واحد لنشر الإعلانات وإدارة الطلبات العقارية ضمن حدود الباقة.'
          : '$planName — one account to publish listings and manage property requests within plan limits.';
    }
    if (order == 2 || order == 3) {
      return isAr
          ? 'باقة $planName — للمكاتب والفرق؛ إدارة الإعلانات والطلبات وإتمام الصفقات ضمن حدود الباقة.'
          : '$planName — for offices and teams; manage listings, requests, and deals within plan limits.';
    }
    return isAr
        ? 'باقة $planName — اشتراك مدفوع يمنحك حصص استخدام داخل المنصة حسب الجدول أدناه.'
        : '$planName — a paid subscription with the usage quotas listed below.';
  }

  /// سطر سياسة الاشتراك تحت البطاقة.
  static String policyLine(Map<String, dynamic> plan, {required String lang}) {
    final isAr = _isAr(lang);
    final sort = _intOf(plan['sort_order']) ?? 0;
    final pct = _autoPayPct(plan).round();
    final yearlyOff = 20;

    if (SubscriptionService.isMarketOffersTopUpSortOrder(sort)) {
      return isAr
          ? '• باقة إضافية — تُضاف حصة «إتمام الصفقة» فور الدفع'
          : '• Add-on — deal quota applies immediately after payment';
    }
    if (SubscriptionService.isComprehensivePlanSortOrder(sort)) {
      return isAr
          ? '• ترقية — حصة «إتمام صفقة» أعلى من الباقة الأساسية'
          : '• Upgrade — higher «Complete deal» quota than the base plan';
    }

    final program =
        (plan['plan_program'] ?? 'monthly').toString().trim().toLowerCase();
    if (program == 'lifetime_one_time') {
      return isAr
          ? '• دفعة واحدة — لا تجديد تلقائي'
          : '• One-time payment — no auto-renewal';
    }

    return isAr
        ? '• حساب واحد — لا إضافة أعضاء • خصم $pct٪ شهرياً مع التجديد التلقائي • السنوي −$yearlyOff٪ بدون تجديد تلقائي'
        : '• One account — no extra seats • $pct% off monthly with auto-renew • Yearly $yearlyOff% off, no auto-renew';
  }

  static String listingsLine(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final isAr = _isAr(lang);
    if (plan['is_trial_plan'] == true) {
      return isAr
          ? '• الإعلانات العقارية (صفحتي): إعلان واحد (تجربة ٣ أيام)'
          : '• Property listings (My desk): 1 listing (3-day trial)';
    }
    final v = plan['max_ads_per_month'];
    final n = _intOf(v);
    final val = (n == null || n <= 0)
        ? (isAr ? 'غير محدود' : 'Unlimited')
        : (isAr ? '$n إعلان / شهر' : '$n listings / month');
    return isAr
        ? '• الإعلانات العقارية / شهرياً: $val'
        : '• Property listings / month: $val';
  }

  static String listingRequestsLine(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final isAr = _isAr(lang);
    final v = plan['max_listing_requests'];
    if (v == null) {
      return isAr
          ? '• طلبات عقارية من الرئيسية: غير محدود'
          : '• Property requests from home: Unlimited';
    }
    final n = _intOf(v) ?? 0;
    if (n <= 0) {
      return isAr
          ? '• طلبات عقارية من الرئيسية: غير مشمولة'
          : '• Property requests from home: Not included';
    }
    return isAr
        ? '• طلبات عقارية من الرئيسية: $n / شهر'
        : '• Property requests from home: $n / month';
  }

  static String marketOffersLine(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final isAr = _isAr(lang);
    if (plan['is_trial_plan'] == true) {
      return isAr
          ? '• إتمام الصفقة على طلبات السوق من الرئيسية: غير محدود (تجربة)'
          : '• Complete deals from home: unlimited (trial)';
    }
    final raw = plan['max_market_offers'];
    if (raw == null) {
      return isAr
          ? '• إتمام الصفقة على طلبات السوق من الرئيسية: غير محدود'
          : '• Complete deals on market requests from home: Unlimited';
    }
    final n = _intOf(raw) ?? 0;
    final program =
        (plan['plan_program'] ?? 'monthly').toString().trim().toLowerCase();
    if (n <= 0) {
      return isAr
          ? '• إتمام الصفقة على طلبات السوق من الرئيسية: غير مشمول (يلزم باقة عروض)'
          : '• Deals from home: not included (requires offer plan)';
    }
    if (program == 'lifetime_one_time') {
      return isAr
          ? '• إتمام الصفقة على طلبات السوق من الرئيسية: $n صفقة (رصيد إجمالي)'
          : '• Deals from home: $n deals (lifetime balance)';
    }
    return isAr
        ? '• إتمام الصفقة على طلبات السوق من الرئيسية: $n صفقة / شهر'
        : '• Deals from home: $n deals / month';
  }

  static String? comprehensiveNote(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final sort = _intOf(plan['sort_order']) ?? 0;
    if (!SubscriptionService.isComprehensivePlanSortOrder(sort)) return null;
    final isAr = _isAr(lang);
    return isAr
        ? '• باقة ترقية — حصة «إتمام صفقة» أعلى؛ تُفعَّل فور الدفع وتظهر في حسابك'
        : '• Upgrade tier — higher deal quota; activates immediately after payment';
  }

  /// أسطر البطاقة تحت اسم الباقة.
  static List<String> cardBulletLines(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final lines = <String>[
      policyLine(plan, lang: lang),
      listingsLine(plan, lang: lang),
      listingRequestsLine(plan, lang: lang),
      marketOffersLine(plan, lang: lang),
    ];
    final note = comprehensiveNote(plan, lang: lang);
    if (note != null) lines.add(note);

    final support = _featureTextFromJson(plan, isAr: _isAr(lang), jsonKey: 'support');
    if (support.isNotEmpty) {
      lines.add('• $support');
    }
    return lines;
  }

  /// قائمة ميزات الباقة (شاشة التفاصيل).
  static List<({String label, bool included})> featureChecklist(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final isAr = _isAr(lang);
    final hasFal = plan['has_fal_license'] == true;
    final hasAnalytics = plan['has_analytics'] == true;
    final hasApi = plan['has_api_access'] == true;
    final hasPriority = plan['has_priority_support'] == true;

    return [
      (
        label: isAr ? 'رخصة فال / شارة الامتثال' : 'FAL license / compliance badge',
        included: hasFal,
      ),
      (
        label: isAr ? 'تحليلات وإحصائيات' : 'Analytics & insights',
        included: hasAnalytics,
      ),
      (
        label: isAr ? 'وصول API' : 'API access',
        included: hasApi,
      ),
      (
        label: isAr ? 'دعم أولوية' : 'Priority support',
        included: hasPriority,
      ),
    ];
  }

  static String marketOffersDetailValue(
    Map<String, dynamic> plan, {
    required String lang,
  }) {
    final isAr = _isAr(lang);
    if (plan['is_trial_plan'] == true) {
      return isAr ? 'غير محدود (تجربة)' : 'Unlimited (trial)';
    }
    final raw = plan['max_market_offers'];
    if (raw == null) return isAr ? 'غير محدود' : 'Unlimited';
    final n = _intOf(raw) ?? 0;
    final program =
        (plan['plan_program'] ?? 'monthly').toString().trim().toLowerCase();
    if (n <= 0) {
      return isAr
          ? 'غير مشمول — يلزم باقة عروض منفصلة'
          : 'Not included — requires a separate offers plan';
    }
    if (program == 'lifetime_one_time') {
      return isAr ? '$n صفقة (رصيد إجمالي)' : '$n deals (lifetime balance)';
    }
    return isAr ? '$n صفقة / شهر' : '$n deals / month';
  }

  static String limitLabel(
    dynamic v, {
    required String lang,
    String? unitAr,
    String? unitEn,
  }) {
    final isAr = _isAr(lang);
    final lim = _lim(v, isAr: isAr);
    if (unitAr != null && unitEn != null && lim != (isAr ? 'غير محدود' : 'Unlimited')) {
      return isAr ? '$lim $unitAr' : '$lim $unitEn';
    }
    return lim;
  }
}
