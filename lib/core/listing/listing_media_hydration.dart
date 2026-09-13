import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_media_urls.dart';

/// يربط وسائط الإعلان بصف العقار حتى تظهر في البطاقات والرئيسية والشورتز
/// حتى لو فشل تضمين PostgREST لجدول `property_images`.
abstract final class ListingMediaHydration {
  static Map<String, dynamic>? guidanceMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  static bool _embedEmpty(dynamic raw) {
    if (raw == null) return true;
    if (raw is List) return raw.isEmpty;
    if (raw is Map) return raw.isEmpty;
    return true;
  }

  /// ينسخ مسارات الصور/الفيديو/الجولة من `listing_guidance` و`image_url` إلى شكل الصف.
  static void stampRow(Map row) {
    final g = guidanceMap(row['listing_guidance']);
    final payloadMap = guidanceMap(row['payload_json']);
    final fromGuidance = ListingMediaUrls.imagePathsFromPayload(g);
    final fromPayload = ListingMediaUrls.imagePathsFromPayload(payloadMap);
    final cover = (row['image_url'] ?? row['primary_image'] ?? '')
        .toString()
        .trim();
    final merged = ListingMediaUrls.mergePathLists([
      fromGuidance,
      fromPayload,
      if (cover.isNotEmpty &&
          !ListingMediaUrls.isSmartDefaultCoverPath(cover) &&
          !ListingMediaUrls.looksLikeVideoPath(cover))
        [cover],
    ]);

    if (merged.isNotEmpty && _embedEmpty(row['property_images'])) {
      row['images'] = merged;
      row['property_images'] = [
        for (var i = 0; i < merged.length; i++)
          <String, dynamic>{
            'path': merged[i],
            'file_name': merged[i],
            'sort_order': i,
          },
      ];
    }

    final vidG = ListingMediaUrls.videoPathFromPayload(g) ??
        ListingMediaUrls.videoPathFromPayload(payloadMap);
    if ((row['video_url'] ?? '').toString().trim().isEmpty &&
        (vidG ?? '').trim().isNotEmpty) {
      row['video_url'] = vidG!.trim();
    }

    final tourG = (ListingMediaUrls.virtualTourFromPayload(g) ??
            ListingMediaUrls.virtualTourFromPayload(payloadMap) ??
            '')
        .trim();
    if ((row['virtual_tour_url'] ?? '').toString().trim().isEmpty &&
        tourG.isNotEmpty) {
      row['virtual_tour_url'] = tourG;
    }
  }

  static Future<void> hydratePropertyRows(
    SupabaseClient sb,
    List<Map> rows,
  ) async {
    if (rows.isEmpty) return;
    for (final r in rows) {
      stampRow(r);
    }

    final need = <String>[];
    for (final r in rows) {
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      if (!_embedEmpty(r['property_images'])) continue;
      final paths = ListingMediaUrls.imagePathsFromPropertyImages(
        r['property_images'],
      );
      if (paths.isEmpty) need.add(id);
    }
    if (need.isEmpty) return;

    try {
      final data = await sb
          .from('property_images')
          .select('property_id,path,file_name,url,sort_order,media_type')
          .inFilter('property_id', need);
      final byPid = <String, List<Map<String, dynamic>>>{};
      for (final e in (data as List)) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final pid = (m['property_id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        byPid.putIfAbsent(pid, () => []).add(m);
      }
      for (final r in rows) {
        final id = (r['id'] ?? '').toString().trim();
        final imgs = byPid[id];
        if (imgs == null || imgs.isEmpty) continue;
        r['property_images'] = imgs;
      }
    } catch (_) {}

    for (final r in rows) {
      stampRow(r);
    }
  }
}
