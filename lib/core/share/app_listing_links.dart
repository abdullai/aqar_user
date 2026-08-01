/// روابط فتح إعلان محدد على الويب (ومشاركة النص).
/// غيّر القيمة عبر: `--dart-define=WEB_APP_ORIGIN=https://your-host.web.app`
abstract final class AppListingLinks {
  static const String _kOrigin = String.fromEnvironment(
    'WEB_APP_ORIGIN',
    defaultValue: 'https://eaqar-mawthuq.web.app',
  );

  static const String pendingListingPrefKey = 'pending_open_listing_id';

  /// رابط عقد (?contract=&verify=1) عند فتح التطبيق من App Links (أندرويد/آي أو إس).
  static const String pendingContractVerifyPrefKey =
      'pending_open_contract_verify_id';

  static const String pendingContractVerifyTokenPrefKey =
      'pending_open_contract_verify_token';

  static String get webOrigin {
    final o = _kOrigin.trim();
    if (o.isEmpty) return 'https://eaqar-mawthuq.web.app';
    return o.replaceAll(RegExp(r'/$'), '');
  }

  /// `https://host/?listing=<uuid>&lang=ar|en`
  static Uri listingWebUri(String propertyId, {required String lang}) {
    final id = propertyId.trim();
    final l = lang.toLowerCase() == 'en' ? 'en' : 'ar';
    final base = Uri.parse(webOrigin);
    return base.replace(
      queryParameters: {
        'listing': id,
        'lang': l,
      },
    );
  }

  /// `https://host/?market_request=<uuid>&lang=ar|en` — مشاركة/نسخ طلب سوق (يفتح التطبيق/الويب عند دعم المسار).
  static Uri marketRequestWebUri(String requestId, {required String lang}) {
    final id = requestId.trim();
    final l = lang.toLowerCase() == 'en' ? 'en' : 'ar';
    final base = Uri.parse(webOrigin);
    return base.replace(
      queryParameters: {
        'market_request': id,
        'lang': l,
      },
    );
  }

  /// `https://host/?contract=<uuid>&verify=1&lang=ar|en` — التحقق من عقد تسويق (مسح QR).
  /// [verifyToken] يُضاف كـ `vt` ويُطابق `listing_contracts.verify_public_token`.
  static Uri contractVerifyWebUri(
    String contractId, {
    required String lang,
    String? verifyToken,
  }) {
    final id = contractId.trim();
    final l = lang.toLowerCase() == 'en' ? 'en' : 'ar';
    final base = Uri.parse(webOrigin);
    final vt = verifyToken?.trim();
    return base.replace(
      queryParameters: {
        'contract': id,
        'verify': '1',
        'lang': l,
        if (vt != null && vt.isNotEmpty) 'vt': vt,
      },
    );
  }

  /// `motawoq://verify?contract=&verify=1&lang=&vt=` — فتح داخل التطبيق بعد تسجيل الدخول.
  static Uri contractVerifyAppUri(
    String contractId, {
    required String lang,
    String? verifyToken,
  }) {
    final id = contractId.trim();
    final l = lang.toLowerCase() == 'en' ? 'en' : 'ar';
    final vt = verifyToken?.trim();
    return Uri(
      scheme: 'motawoq',
      host: 'verify',
      queryParameters: {
        'contract': id,
        'verify': '1',
        'lang': l,
        if (vt != null && vt.isNotEmpty) 'vt': vt,
      },
    );
  }

  static String? contractIdFromVerifyUri(Uri? uri) {
    if (uri == null) return null;
    final v = uri.queryParameters['verify']?.trim();
    if (v != '1' && v != 'true') return null;
    final c = uri.queryParameters['contract']?.trim();
    return (c != null && c.isNotEmpty) ? c : null;
  }

  static String? verifyTokenFromVerifyUri(Uri? uri) {
    if (uri == null) return null;
    final v = uri.queryParameters['verify']?.trim();
    if (v != '1' && v != 'true') return null;
    final t = uri.queryParameters['vt']?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static String? listingIdFromUri(Uri? uri) {
    if (uri == null) return null;
    var q = uri.queryParameters['listing']?.trim();
    if (q != null && q.isNotEmpty) return q;
    if (uri.scheme == 'aqar' && uri.host == 'listing') {
      q = uri.queryParameters['listing']?.trim();
      if (q != null && q.isNotEmpty) return q;
    }
    return null;
  }
}
