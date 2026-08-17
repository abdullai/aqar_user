import 'dart:convert';

/// استخراج أفضل تقدير لسعر العقار (ريال) لحساب عمولة التسويق.
double effectivePropertyPriceSarForMarketingFee(
  Map<String, dynamic> request, [
  Map<String, dynamic>? linkedProperty,
]) {
  double fromDyn(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? 0;
  }

  double fromMap(Map<String, dynamic> m) {
    for (final k in [
      'price',
      'offer_price',
      'base_price',
      'property_price',
      'total_price',
      'asking_price',
      'expected_price',
    ]) {
      final x = fromDyn(m[k]);
      if (x > 0) return x;
    }
    return 0;
  }

  if (linkedProperty != null) {
    final p = fromDyn(linkedProperty['price']);
    if (p > 0) return p;
    final alt = fromMap(linkedProperty);
    if (alt > 0) return alt;
  }

  for (final k in [
    'price',
    'request_price',
    'preview_price',
    'listing_price',
    'property_price',
    'total_price',
    'asking_price',
  ]) {
    final x = fromDyn(request[k]);
    if (x > 0) return x;
  }

  final pay = request['payload'];
  if (pay is Map) {
    final x = fromMap(Map<String, dynamic>.from(pay));
    if (x > 0) return x;
  }

  final pj = request['payload_json'];
  if (pj is Map) {
    final x = fromMap(Map<String, dynamic>.from(pj));
    if (x > 0) return x;
  }
  if (pj is String && pj.trim().startsWith('{')) {
    try {
      final d = jsonDecode(pj);
      if (d is Map) {
        final x = fromMap(Map<String, dynamic>.from(d));
        if (x > 0) return x;
      }
    } catch (_) {}
  }

  return 0;
}
