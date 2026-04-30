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

  /// `https://host/?contract=<uuid>&verify=1&lang=ar|en` — التحقق من عقد تسويق (مسح QR).
  static Uri contractVerifyWebUri(String contractId, {required String lang}) {
    final id = contractId.trim();
    final l = lang.toLowerCase() == 'en' ? 'en' : 'ar';
    final base = Uri.parse(webOrigin);
    return base.replace(
      queryParameters: {
        'contract': id,
        'verify': '1',
        'lang': l,
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
