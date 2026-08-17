import '../input/input_normalizers.dart';

/// حمولة QR آمنة لانضمام الفريق: ليست رقم جوال، بل رمز تسجيل (`recruit_join_code`) مع بادئة إصدار.
abstract final class OrgJoinQrPayload {
  static const String prefix = 'aqar_team_join_v1:';

  /// يُرمَز به الـ QR ومشاركة «نسخ الرابط».
  static String encodeRecruitCode(String tenDigitCode) {
    final d = digitsOnly(normalizeAsciiDigits(tenDigitCode.trim()));
    return '$prefix$d';
  }

  /// يقبل النص الخام من الماسح أو لصق يدوي.
  static String parseRecruitOrOrgInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith(prefix)) {
      return digitsOnly(normalizeAsciiDigits(s.substring(prefix.length)));
    }
    final lower = s.toLowerCase();
    final uri = Uri.tryParse(s);
    if (uri != null &&
        uri.scheme == 'aqar' &&
        uri.host == 'team-join' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'v1') {
      final c = uri.queryParameters['c'] ?? uri.pathSegments.last;
      return digitsOnly(normalizeAsciiDigits(c));
    }
    if (lower.contains('aqar') && lower.contains('team') && lower.contains('join')) {
      final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
      final c = u?.queryParameters['c'] ?? u?.queryParameters['code'];
      if (c != null && c.isNotEmpty) {
        return digitsOnly(normalizeAsciiDigits(c));
      }
    }
    return digitsOnly(normalizeAsciiDigits(s));
  }
}
