/// سطح حسّاس: رجوع المتصفح = إنهاء الجلسة لا التنقّل داخل التطبيق.
abstract final class SensitiveNavPolicy {
  SensitiveNavPolicy._();

  static int _deleteListingDepth = 0;
  static int _verifyDepth = 0;

  static bool get isDeleteListingOpen => _deleteListingDepth > 0;

  static bool get isVerifyOpen => _verifyDepth > 0;

  static void enterDeleteListing() => _deleteListingDepth++;

  static void leaveDeleteListing() {
    if (_deleteListingDepth > 0) _deleteListingDepth--;
  }

  static void enterVerify() => _verifyDepth++;

  static void leaveVerify() {
    if (_verifyDepth > 0) _verifyDepth--;
  }

  static bool isVerifyRouteName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    return n == '/verify' || n == 'verify' || n.endsWith('/verify');
  }

  static bool isAuthGateRouteName(String? name) {
    final n = (name ?? '').trim();
    final low = n.toLowerCase();
    return n == '/login' ||
        n == '/fastLogin' ||
        n == '/fastlogin' ||
        n == '/entryChoice' ||
        n == '/entrychoice' ||
        n == '/gate' ||
        n == '/resetPassword' ||
        n == '/resetpassword' ||
        n == '/passwordSetup' ||
        n == '/passwordsetup' ||
        low == '/legalterms' ||
        low == '/legal-terms-acceptance';
  }

  /// لا يُعاد فتحه بسهم التقدّم (OTP / بوابات الدخول).
  static bool isSensitiveReplayName(String? name) {
    if (isVerifyRouteName(name)) return true;
    if (isAuthGateRouteName(name)) return true;
    return false;
  }
}
