import '../utils/dashboard_greeting.dart';
import '../utils/display_ids.dart';

/// موضوع النص الافتتاحي — صياغة ذكية حسب نوع المراسلة.
enum MarketerOwnerChatIntroSubject {
  /// إعلان عقاري منشور / معاينة.
  listing,

  /// طلب تسويق / طلب سوق.
  request,

  /// صفقة نشطة بين طرفين على طلب أو إعلان.
  deal,
}

/// نص تمهيدي لمراسلة المالك (داخل التطبيق أو واتساب).
///
/// يظهر الاسم مرة واحدة (بدون تكرار «شريكنا العقاري»)، ورقم العرض إن وُجد.
abstract final class MarketerOwnerChatIntroAr {
  static final RegExp _tenDigitRe = RegExp(r'^[0-9]{10}$');

  static bool _isGenericPartnerLabel(String raw, {required bool isAr}) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (isAr) {
      return t == 'شريكنا العقاري' ||
          t == 'الشريك العقاري' ||
          t == 'المالك' ||
          t == 'مسوّق' ||
          t == 'مسوق';
    }
    return lower == 'property owner' ||
        lower == 'real estate partner' ||
        lower == 'our partner' ||
        lower == 'owner' ||
        lower == 'partner';
  }

  /// يستخرج رقم العرض العام (10 خانات) من صف طلب/إعلان بأي مفتاح شائع.
  static String tenDigitListingCodeFromRow(Map<String, dynamic> row) {
    const keys = <String>[
      'listing_request_public_code',
      'preview_listing_public_code',
      'listing_public_code',
      'public_listing_code',
      'property_public_code',
      'preview_public_code',
      'request_public_code',
      'public_code',
      'listing_code',
      'display_code',
      'listing_no',
      'ad_number',
    ];
    for (final k in keys) {
      final raw = (row[k] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length >= 10) {
        return DisplayIds.tenDigit(digits);
      }
      if (_tenDigitRe.hasMatch(raw)) {
        return DisplayIds.tenDigit(raw);
      }
    }

    // احتياط: أي قيمة رقمية ظاهرة في الصف (بدون توليد هاش عشوائي من UUID).
    for (final k in const [
      'listing_request_number',
      'request_number',
      'ad_no',
      'property_number',
    ]) {
      final raw = (row[k] ?? '').toString().trim();
      final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length >= 6) {
        return digits.length >= 10
            ? DisplayIds.tenDigit(digits)
            : digits;
      }
    }
    return '';
  }

  /// يخمن الموضوع من مفاتيح الصف إن لم يُمرَّر صراحة.
  static MarketerOwnerChatIntroSubject inferSubject(Map<String, dynamic> row) {
    final kind = (row['conversation_kind'] ??
            row['deal_kind'] ??
            row['subject'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (kind.contains('deal') || kind.contains('صفق')) {
      return MarketerOwnerChatIntroSubject.deal;
    }
    if (kind.contains('request') || kind.contains('طلب')) {
      return MarketerOwnerChatIntroSubject.request;
    }
    final hasListing = (row['preview_property_id'] ??
            row['property_id'] ??
            row['listing_id'] ??
            '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasRequest = (row['request_id'] ??
            row['listing_request_id'] ??
            row['market_request_id'] ??
            '')
        .toString()
        .trim()
        .isNotEmpty;
    if (hasListing && !hasRequest) return MarketerOwnerChatIntroSubject.listing;
    if (hasRequest && !hasListing) return MarketerOwnerChatIntroSubject.request;
    if (hasListing && hasRequest) return MarketerOwnerChatIntroSubject.deal;
    return MarketerOwnerChatIntroSubject.listing;
  }

  static String build({
    required bool isAr,
    required String ownerDisplayName,
    required String listingNoTenDigit,
    required String locationLine,
    MarketerOwnerChatIntroSubject subject = MarketerOwnerChatIntroSubject.listing,
  }) {
    final salute = DashboardGreeting.salutationOnly(isAr: isAr);
    final brand = DashboardGreeting.partnerBrand(isAr: isAr);
    final rawName = ownerDisplayName.trim();
    // اسم حقيقي مرة واحدة — وإلا العلامة التجارية مرة واحدة فقط (بدون تكرار).
    final address = _isGenericPartnerLabel(rawName, isAr: isAr)
        ? brand
        : rawName;

    final loc = locationLine.trim().isEmpty
        ? (isAr ? 'الموقع المذكور' : 'the listed location')
        : locationLine.trim();

    var no = listingNoTenDigit.trim();
    if (no.isEmpty) {
      no = isAr ? 'قيد التعيين' : 'pending';
    }

    if (isAr) {
      final about = switch (subject) {
        MarketerOwnerChatIntroSubject.listing =>
          'بخصوص إعلانكم العقاري رقم $no في $loc',
        MarketerOwnerChatIntroSubject.request =>
          'بخصوص طلبكم العقاري رقم $no في $loc',
        MarketerOwnerChatIntroSubject.deal =>
          'بخصوص صفقتكم على الطلب/الإعلان العقاري رقم $no في $loc',
      };
      return 'السلام عليكم ورحمة الله وبركاته، $salute $address، $about، '
          'هذه بداية محادثة الصفقة بيننا داخل المنصة. '
          'يسعدني التنسيق معكم خطوة بخطوة.';
    }

    final aboutEn = switch (subject) {
      MarketerOwnerChatIntroSubject.listing =>
        'regarding your property listing no. $no in $loc',
      MarketerOwnerChatIntroSubject.request =>
        'regarding your property request no. $no in $loc',
      MarketerOwnerChatIntroSubject.deal =>
        'regarding your deal on listing/request no. $no in $loc',
    };
    return 'Peace be upon you, $salute $address — $aboutEn. '
        'This is the start of our in-app deal chat. '
        'I look forward to coordinating with you step by step.';
  }

  /// هل يبدو النص رسالة افتتاحية للمنصة؟
  static bool looksLikeOpeningIntro(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.contains('السلام عليكم ورحمة الله وبركاته')) return true;
    if (t.contains('هذه بداية محادثة الصفقة')) return true;
    if (t.contains('لدي الرغبة بالتواصل معكم')) return true;
    if (t.toLowerCase().contains('peace be upon you')) return true;
    if (t.toLowerCase().contains('start of our in-app deal chat')) return true;
    if (t.toLowerCase().contains('regarding your property listing')) {
      return true;
    }
    return false;
  }

  /// رسالة قديمة بعيوب معروفة (تكرار العلامة أو رقم فارغ).
  static bool needsLegacyRepair(String raw) {
    if (!looksLikeOpeningIntro(raw)) return false;
    final t = raw;
    if (t.contains('شريكنا العقاري شريكنا العقاري')) return true;
    if (t.contains('رقم —') || t.contains('رقم -') || t.contains('رقم–')) {
      return true;
    }
    if (t.contains('no. —') || t.contains('no. -')) return true;
    if (t.contains('رقم قيد التعيين') || t.contains('no. pending')) {
      return true;
    }
    return false;
  }

  /// إصلاح عرض/محتوى رسالة افتتاحية قديمة دون تغيير بقية النص.
  static String repairLegacyIntro(
    String raw, {
    required String partnerName,
    required String listingCode,
    required bool isAr,
  }) {
    var out = raw.trim();
    if (out.isEmpty) return out;

    final brand = DashboardGreeting.partnerBrand(isAr: isAr);
    final name = partnerName.trim();
    final address = name.isEmpty || _isGenericPartnerLabel(name, isAr: isAr)
        ? brand
        : name;

    out = out.replaceAll('شريكنا العقاري شريكنا العقاري', address);
    // إن بقي الاسم العام مكرراً بصيغة أخرى.
    out = out.replaceAll('$brand $brand', address);

    final code = listingCode.trim();
    if (code.isNotEmpty) {
      out = out
          .replaceAll('رقم —', 'رقم $code')
          .replaceAll('رقم -', 'رقم $code')
          .replaceAll('رقم–', 'رقم $code')
          .replaceAll('رقم قيد التعيين', 'رقم $code')
          .replaceAll('no. —', 'no. $code')
          .replaceAll('no. -', 'no. $code')
          .replaceAll('no. pending', 'no. $code');
    }

    // إن وُجد الاسم الحقيقي ولم يظهر بعد التحية: أدرجه بدل العلامة مرة واحدة.
    if (name.isNotEmpty &&
        !_isGenericPartnerLabel(name, isAr: isAr) &&
        !out.contains(name) &&
        out.contains(brand)) {
      out = out.replaceFirst(brand, name);
    }

    return out;
  }

  /// تنظيف فوري للعرض حتى قبل تحديث الصف في الخادم.
  static String displaySanitize(
    String raw, {
    String? partnerName,
    String? listingCode,
    required bool isAr,
  }) {
    if (!looksLikeOpeningIntro(raw)) return raw;
    if (!needsLegacyRepair(raw) &&
        (partnerName == null || partnerName.trim().isEmpty) &&
        (listingCode == null || listingCode.trim().isEmpty)) {
      return raw;
    }
    return repairLegacyIntro(
      raw,
      partnerName: partnerName ?? '',
      listingCode: listingCode ?? '',
      isAr: isAr,
    );
  }
}
