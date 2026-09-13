import 'package:supabase_flutter/supabase_flutter.dart';

import '../branding/app_branding.dart';
import '../../models/market_property_request_row.dart';
import '../../models/property.dart';

/// روابط موحّدة لصور/فيديو الإعلان والطلب (بطاقات، تفاصيل، عروض، مشاركة).
///
/// شعار التطبيق يظهر فقط عند غياب وسائط حقيقية. وجود صور أو فيديو يلغي
/// [Property.defaultCoverUsed] في العرض.
abstract final class ListingMediaUrls {
  static const _imageBucket = 'property-images';
  static const _videoExt = [
    '.mp4',
    '.mov',
    '.webm',
    '.m4v',
    '.avi',
    '.mkv',
    '.mpeg',
    '.mpg',
  ];

  static const _imageExt = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.svg',
    '.bmp',
    '.heic',
  ];

  static String get defaultThumbAsset => AppBranding.listingPlaceholderAsset;

  static bool isSmartDefaultCoverPath(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return true;
    return p == AppBranding.smartDefaultCoverStorageSentinel;
  }

  static bool looksLikeVideoPath(String? path) {
    final raw = (path ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    final noQuery = raw.split('?').first;
    if (_videoExt.any(noQuery.endsWith)) return true;
    if (raw.contains('video/') || raw == 'video') return true;
    return false;
  }

  static bool _pathLooksLikeImage(String raw) {
    final noQuery = raw.trim().toLowerCase().split('?').first.split('#').first;
    return _imageExt.any(noQuery.endsWith);
  }

  static bool looksLikeEmbeddableVideoHost(String? raw) {
    final u = Uri.tryParse((raw ?? '').trim());
    if (u == null || u.host.isEmpty) return false;
    final h = u.host.toLowerCase();
    return h.contains('youtube.com') ||
        h.contains('youtu.be') ||
        h.contains('youtube-nocookie.com') ||
        h.contains('vimeo.com') ||
        h.contains('player.vimeo.com') ||
        h.contains('loom.com');
  }

  static bool _looksLikeStoredVideoObject(String raw) {
    final l = raw.toLowerCase();
    return l.contains('property-video') ||
        l.contains('/videos/') ||
        l.contains('video/upload') ||
        l.contains('/video/') ||
        l.contains('feed-videos');
  }

  /// مرجع فيديو قابل للتشغيل فعلياً — ليس صورة أو كلمة «video» أو غلاف ذكي.
  static bool looksLikePlayableVideoRef(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty || isSmartDefaultCoverPath(v)) return false;
    if (v.toLowerCase() == 'video') return false;
    if (_pathLooksLikeImage(v)) return false;
    if (looksLikeVideoPath(v)) return true;
    if (looksLikeEmbeddableVideoHost(v)) return true;
    if (_looksLikeStoredVideoObject(v)) return true;
    final u = Uri.tryParse(v);
    if (u != null &&
        (u.isScheme('http') || u.isScheme('https')) &&
        u.host.isNotEmpty) {
      // رابط عام بلا امتداد فيديو: لا نُظهر تبويب الوسائط — غالباً صورة/موقع.
      return false;
    }
    return false;
  }

  static bool isPlayableHttpUrl(String? raw) {
    final u = Uri.tryParse((raw ?? '').trim());
    if (u == null || u.host.isEmpty) return false;
    return u.isScheme('http') || u.isScheme('https');
  }

  /// رابط جولة افتراضية قابل للفتح — ليس صورة ولا فيديو ولا أي موقع عشوائي.
  static bool looksLikePlayableTourUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (!isPlayableHttpUrl(v) || _pathLooksLikeImage(v)) return false;
    if (looksLikeVideoPath(v)) return false;
    if (looksLikeEmbeddableVideoHost(v)) return true;
    final l = v.toLowerCase();
    return l.contains('matterport') ||
        l.contains('kuula') ||
        l.contains('roundme') ||
        l.contains('cloudpano') ||
        l.contains('pano') ||
        l.contains('360') ||
        l.contains('/tour') ||
        l.contains('virtualtour') ||
        l.contains('virtual-tour') ||
        l.contains('3d');
  }

  static bool rowLooksLikeVideo(Map<String, dynamic> row) {
    final mt = (row['media_type'] ?? '').toString().trim().toLowerCase();
    if (mt.contains('video')) return true;
    return looksLikeVideoPath(
      (row['path'] ?? row['file_name'] ?? row['url'] ?? '').toString(),
    );
  }

  static List<String> imagePathsExcludingVideo(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item.trim();
      if (s.isEmpty || isSmartDefaultCoverPath(s) || looksLikeVideoPath(s)) {
        continue;
      }
      final key = _dedupeKey(s);
      if (!seen.add(key)) continue;
      out.add(s);
    }
    return out;
  }

  static bool propertyHasRealMedia(Property p) =>
      imagePathsExcludingVideo(p.images).isNotEmpty ||
      looksLikePlayableVideoRef(p.videoUrl) ||
      looksLikePlayableTourUrl(p.virtualTourUrl);

  /// غلاف ذكي فقط إن لم توجد صورة ولا فيديو حقيقي — لا يُخفى الإعلام عند العلم وحده.
  static bool propertyUsesSmartDefaultCover(Property p) =>
      !propertyHasRealMedia(p);

  static bool marketRequestUsesSmartDefaultCover(MarketPropertyRequestRow r) =>
      isSmartDefaultCoverPath(r.coverImageStoragePath);

  static bool propertyPrefersVideoCover(Property p) {
    // استخدم ?. دائماً — dart2js (Dart 3.12) يرفض [] على Map<String, dynamic>?.
    final v = (p.listingGuidance?['cover_primary'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (v == 'video') return true;
    if (v == 'image') return false;
    return imagePathsExcludingVideo(p.images).isEmpty &&
        (p.videoUrl ?? '').trim().isNotEmpty;
  }

  /// مسارات الصور للبطاقات — لا تُفرَّغ بسبب علم الغلاف الذكي إن وُجدت صور.
  static List<String> propertyCardImagePaths(Property p) =>
      imagePathsExcludingVideo(p.images);

  static String fallbackSharePreviewImageUrl() =>
      AppBranding.webEstablishmentCoverShareUrl();

  static String? videoPlayableUrl(SupabaseClient sb, String? pathOrUrl) {
    final s = (pathOrUrl ?? '').trim();
    if (s.isEmpty || isSmartDefaultCoverPath(s)) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    try {
      if (looksLikeVideoPath(s) || !s.contains('/')) {
        return sb.storage.from('property-videos').getPublicUrl(s);
      }
    } catch (_) {}
    return storagePublicUrl(sb, s);
  }

  static String? storagePublicUrl(SupabaseClient sb, String? pathOrUrl) {
    final s = (pathOrUrl ?? '').trim();
    if (s.isEmpty || isSmartDefaultCoverPath(s)) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    try {
      return sb.storage.from(_imageBucket).getPublicUrl(s);
    } catch (_) {
      return null;
    }
  }

  static List<String> publicUrls(
    SupabaseClient sb,
    Iterable<dynamic> paths,
  ) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in paths) {
      final u = storagePublicUrl(sb, raw?.toString());
      if (u == null || u.isEmpty) continue;
      if (!seen.add(_dedupeKey(u))) continue;
      out.add(u);
    }
    return out;
  }

  static List<String> mergePathLists(Iterable<Iterable<dynamic>> groups) {
    final out = <String>[];
    final seen = <String>{};
    for (final group in groups) {
      for (final raw in group) {
        final s = raw.toString().trim();
        if (s.isEmpty || isSmartDefaultCoverPath(s) || looksLikeVideoPath(s)) {
          continue;
        }
        if (!seen.add(_dedupeKey(s))) continue;
        out.add(s);
      }
    }
    return out;
  }

  static String? propertyImageNetworkUrl(Property p, SupabaseClient sb) {
    if (!propertyHasRealMedia(p)) return null;
    for (final raw in propertyCardImagePaths(p)) {
      final u = storagePublicUrl(sb, raw);
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  static String? marketRequestCoverNetworkUrl(
    MarketPropertyRequestRow r,
    SupabaseClient sb,
  ) {
    final path = (r.coverImageStoragePath ?? '').trim();
    if (path.isNotEmpty && !isSmartDefaultCoverPath(path)) {
      return storagePublicUrl(sb, path);
    }
    final fromDetails = imagePathsFromPayload(r.details);
    for (final raw in fromDetails) {
      final s = raw.trim();
      if (s.isEmpty || isSmartDefaultCoverPath(s) || looksLikeVideoPath(s)) {
        continue;
      }
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return storagePublicUrl(sb, s);
    }
    return null;
  }

  static String propertySharePreviewHttpUrl(Property p, SupabaseClient sb) =>
      propertyImageNetworkUrl(p, sb) ?? fallbackSharePreviewImageUrl();

  static String marketRequestSharePreviewHttpUrl(
    MarketPropertyRequestRow r,
    SupabaseClient sb,
  ) =>
      marketRequestCoverNetworkUrl(r, sb) ?? fallbackSharePreviewImageUrl();

  static List<String> imagePathsFromPropertyImages(dynamic raw) {
    final rows = <Map<String, dynamic>>[];
    if (raw is Map) {
      rows.add(Map<String, dynamic>.from(raw));
    } else if (raw is List) {
      for (final e in raw) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    }
    rows.sort((a, b) {
      final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
      final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
      return sa.compareTo(sb);
    });
    final out = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      if (rowLooksLikeVideo(row)) continue;
      final path = (row['path'] ??
              row['file_name'] ??
              row['url'] ??
              row['file_path'] ??
              row['storage_path'] ??
              '')
          .toString()
          .trim();
      if (path.isEmpty || isSmartDefaultCoverPath(path)) continue;
      if (!seen.add(_dedupeKey(path))) continue;
      out.add(path);
    }
    return out;
  }

  static String? videoPathFromPropertyImages(dynamic raw) {
    final rows = <Map<String, dynamic>>[];
    if (raw is Map) {
      rows.add(Map<String, dynamic>.from(raw));
    } else if (raw is List) {
      for (final e in raw) {
        if (e is Map) rows.add(Map<String, dynamic>.from(e));
      }
    }
    for (final row in rows) {
      if (!rowLooksLikeVideo(row)) continue;
      final path = (row['path'] ?? row['file_name'] ?? row['url'] ?? '')
          .toString()
          .trim();
      if (path.isNotEmpty) return path;
    }
    return null;
  }

  static List<String> imagePathsFromPayload(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) return const [];
    final flat = Map<String, dynamic>.from(payload);
    final lg = payload['listing_guidance'];
    if (lg is Map) {
      for (final e in Map<String, dynamic>.from(lg).entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
    }
    for (final k in const [
      'request_image_paths',
      'image_paths',
      'image_urls',
      'images',
      'photos',
      'gallery',
      'property_images',
      'preview_image_urls',
    ]) {
      final fromKey = _pathsFromDynamic(flat[k]);
      if (fromKey.isNotEmpty) return fromKey;
    }
    for (final k in const [
      'cover_image',
      'main_image',
      'image',
      'thumbnail',
      'listing_image',
      'photo',
      'photo_url',
      'hero_image',
      'primary_image',
      'primaryImage',
    ]) {
      final s = (flat[k] ?? '').toString().trim();
      if (s.isEmpty || isSmartDefaultCoverPath(s) || looksLikeVideoPath(s)) {
        continue;
      }
      return [s];
    }
    return const [];
  }

  static String? videoPathFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final flat = Map<String, dynamic>.from(payload);
    final lg = payload['listing_guidance'];
    if (lg is Map) {
      for (final e in Map<String, dynamic>.from(lg).entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
    }
    for (final k in const [
      'request_video_path',
      'video_url',
      'video_path',
      'video',
    ]) {
      final s = (flat[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static String? virtualTourFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final flat = Map<String, dynamic>.from(payload);
    final lg = payload['listing_guidance'];
    if (lg is Map) {
      for (final e in Map<String, dynamic>.from(lg).entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
    }
    for (final k in const ['virtual_tour_url', 'tour_url', 'virtualTourUrl']) {
      final s = (flat[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static bool payloadPrefersVideoCover(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final raw = payload['listing_guidance'];
    if (raw is Map) {
      final g = Map<String, dynamic>.from(raw);
      return (g['cover_primary'] ?? '').toString().trim().toLowerCase() ==
          'video';
    }
    return (payload['cover_primary'] ?? '').toString().trim().toLowerCase() ==
        'video';
  }

  static List<String> _pathsFromDynamic(dynamic raw) {
    final out = <String>[];
    final seen = <String>{};
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || isSmartDefaultCoverPath(t) || looksLikeVideoPath(t)) {
        return;
      }
      if (!seen.add(_dedupeKey(t))) return;
      out.add(t);
    }

    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          if (rowLooksLikeVideo(m)) continue;
          add((m['path'] ?? m['url'] ?? m['image'] ?? m['image_url'] ?? '')
              .toString());
        } else {
          add(e.toString());
        }
      }
    } else if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      if (!rowLooksLikeVideo(m)) {
        add((m['path'] ?? m['url'] ?? m['image'] ?? '').toString());
      }
    } else if (raw is String) {
      add(raw);
    }
    return out;
  }

  static String _dedupeKey(String s) {
    final t = s.trim().toLowerCase();
    if (t.startsWith('http://') || t.startsWith('https://')) {
      try {
        final u = Uri.parse(t);
        final path = u.path;
        if (path.contains('/property-images/')) {
          return path.split('/property-images/').last;
        }
        if (path.contains('/property-videos/')) {
          return path.split('/property-videos/').last;
        }
        return path;
      } catch (_) {
        return t;
      }
    }
    return t;
  }
}
