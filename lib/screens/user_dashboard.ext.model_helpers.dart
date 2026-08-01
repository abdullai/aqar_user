part of 'user_dashboard.dart';

extension _UserDashboardState_model_helpers on _UserDashboardState {
  static const String _propertyImagesBucket = 'property-images';

  bool _effectiveShowOwnerOnListing(Map row) {
    final show = _toBool(row['show_advertiser_name']) ??
        _toBool(row['show_owner_name']) ??
        true;
    final req = _toBool(row['owner_requests_public_name']) ?? false;
    return show || req;
  }

  Property _propertyFromDb(
    Map row, {
    List<String> imageUrls = const <String>[],
    String? ownerUsername,
    String? ownerPhone,
    bool omitOwnerDisplayForPrivacy = false,
  }) {
    final map = Map<String, dynamic>.from(row);

    return Property.fromDbRow(
      map,
      imageUrls: imageUrls,
      ownerDisplayName: ownerUsername,
      ownerPhone: ownerPhone,
      omitOwnerDisplayForPrivacy: omitOwnerDisplayForPrivacy,
    );
  }

  List<String> _normalizeImageUrls(List<String> xs) {
    final seen = <String>{};
    final out = <String>[];

    for (final raw in xs) {
      final value = _normalizeSingleImage(raw);
      if (value.isEmpty) continue;
      if (seen.add(value)) {
        out.add(value);
      }
    }

    return out;
  }

  String _normalizeSingleImage(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';

    if (_isAbsoluteUrl(v)) return v;

    return _sb.storage.from(_propertyImagesBucket).getPublicUrl(v);
  }

  bool _isAbsoluteUrl(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;

    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;

    return null;
  }
}