import '../utils/dashboard_greeting.dart';
import '../utils/display_ids.dart';

/// نص تمهيدي لمراسلة المالك (داخل التطبيق أو واتساب) — يُعبَّأ في حقل الدردشة.
abstract final class MarketerOwnerChatIntroAr {
  static String tenDigitListingCodeFromRow(Map<String, dynamic> row) {
    var rawCode =
        (row['listing_request_public_code'] ?? '').toString().trim();
    if (rawCode.length != 10 ||
        !RegExp(r'^[0-9]{10}$').hasMatch(rawCode)) {
      rawCode = (row['preview_listing_public_code'] ??
              row['listing_public_code'] ??
              '')
          .toString()
          .trim();
    }
    if (rawCode.length == 10 &&
        RegExp(r'^[0-9]{10}$').hasMatch(rawCode)) {
      return DisplayIds.tenDigit(rawCode);
    }
    return '';
  }

  static String build({
    required bool isAr,
    required String ownerDisplayName,
    required String listingNoTenDigit,
    required String locationLine,
  }) {
    final salute = DashboardGreeting.salutationOnly(isAr: isAr);
    final nm = ownerDisplayName.trim().isEmpty
        ? (isAr ? 'شريكنا العقاري' : 'property owner')
        : ownerDisplayName.trim();
    final loc = locationLine.trim().isEmpty
        ? (isAr ? 'الموقع المذكور في الإعلان' : 'the location listed')
        : locationLine.trim();
    final no = listingNoTenDigit.trim().isEmpty ? '—' : listingNoTenDigit.trim();
    if (isAr) {
      return 'السلام عليكم ورحمة الله وبركاته، $salute شريكنا العقاري $nm، '
          'بخصوص إعلانكم العقاري رقم $no في $loc، لدي الرغبة بالتواصل معكم، '
          'هل وقتكم يسمح بذلك؟ أنتظر إجابتك عندما تكون الفرصة مناسبة لك.';
    }
    return 'Hello, $salute. Dear $nm, regarding your property listing no. $no '
        'in $loc — I would like to connect with you. Please let me know when '
        'a good time works for you. Thank you.';
  }
}
