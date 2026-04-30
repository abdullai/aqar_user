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

  List<Property> _mapRowsToProperties(
    List<dynamic> rows, {
    List<String> Function(Map row)? imageUrlsOfRow,
    String? Function(Map row)? ownerUsernameOfRow,
    String? Function(Map row)? ownerPhoneOfRow,
  }) {
    return rows.whereType<Map>().map((r) {
      final row = Map<String, dynamic>.from(r);

      final builtImages = imageUrlsOfRow?.call(row);
      final fallbackImages = _imageUrlsFromRow(row);

      final showAdvertiserName =
          _toBool(row['show_advertiser_name']) ??
          _toBool(row['show_owner_name']) ??
          true;
      final ownerRequests = _toBool(row['owner_requests_public_name']) ?? false;
      final effectiveShow = showAdvertiserName || ownerRequests;

      final resolvedOwnerName = effectiveShow
          ? _firstNonEmptyString([
              ownerUsernameOfRow?.call(row),
              row['owner_display_name']?.toString(),
              row['username']?.toString(),
              _nestedValue(row, 'account_profiles', 'full_name')?.toString(),
            ])
          : null;

      final resolvedOwnerPhone = _firstNonEmptyString([
        ownerPhoneOfRow?.call(row),
        row['owner_phone']?.toString(),
        row['contact_phone']?.toString(),
        _nestedValue(row, 'account_profiles', 'phone')?.toString(),
      ]);

      return _propertyFromDb(
        row,
        imageUrls: (builtImages != null && builtImages.isNotEmpty)
            ? _normalizeImageUrls(builtImages)
            : fallbackImages,
        ownerUsername: resolvedOwnerName,
        ownerPhone: resolvedOwnerPhone,
        omitOwnerDisplayForPrivacy: !effectiveShow,
      );
    }).toList();
  }

  List<String> _toStringList(List<dynamic> xs) {
    return xs
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _imageUrlsFromRow(Map row) {
    final out = <String>[];

    final propertyImagesRaw = row['property_images'];
    List<Map<String, dynamic>> imageRows;
    if (propertyImagesRaw is Map) {
      imageRows = [Map<String, dynamic>.from(propertyImagesRaw)];
    } else if (propertyImagesRaw is List) {
      imageRows = propertyImagesRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort((a, b) {
          final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
          final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
          return sa.compareTo(sb);
        });
    } else {
      imageRows = const [];
    }

    if (imageRows.isNotEmpty) {
      for (final img in imageRows) {
        final path = (img['path'] ?? '').toString().trim();
        final url = (img['url'] ?? '').toString().trim();
        final fileName = (img['file_name'] ?? '').toString().trim();

        if (path.isNotEmpty) {
          out.add(_normalizeSingleImage(path));
        } else if (url.isNotEmpty) {
          out.add(_normalizeSingleImage(url));
        } else if (fileName.isNotEmpty) {
          out.add(_normalizeSingleImage(fileName));
        }
      }
    }

    if (out.isEmpty) {
      final imagesRaw = row['images'];
      if (imagesRaw is List) {
        out.addAll(
          imagesRaw
              .map((e) => _normalizeSingleImage(e.toString()))
              .where((e) => e.isNotEmpty),
        );
      }
    }

    if (out.isEmpty) {
      final imageUrlsRaw = row['image_urls'];
      if (imageUrlsRaw is List) {
        out.addAll(
          imageUrlsRaw
              .map((e) => _normalizeSingleImage(e.toString()))
              .where((e) => e.isNotEmpty),
        );
      }
    }

    if (out.isEmpty) {
      final imageUrlRaw = (row['image_url'] ?? '').toString().trim();
      if (imageUrlRaw.isNotEmpty) {
        out.add(_normalizeSingleImage(imageUrlRaw));
      }
    }

    return _normalizeImageUrls(out);
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

  dynamic _nestedValue(Map row, String parentKey, String childKey) {
    final parent = row[parentKey];
    if (parent is Map) {
      return parent[childKey];
    }
    return null;
  }

  String? _firstNonEmptyString(List<String?> values) {
    for (final v in values) {
      final s = (v ?? '').trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}