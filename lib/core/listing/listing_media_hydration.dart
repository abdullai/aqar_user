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

  static Map<String, dynamic> resolveRow({
    Map<String, dynamic>? property,
    Map<String, dynamic>? request,
  }) {
    final row = <String, dynamic>{...?property};
    if (request != null) {
      row['payload_json'] = request['payload_json'] ?? request['payload'];
      for (final key in const [
        'request_image_paths',
        'image_paths',
        'image_urls',
        'preview_image_urls',
        'request_video_path',
        'video_url',
        'preview_video_url',
        'virtual_tour_url',
        'tour_url',
        'preview_tour_url',
        'preview_virtual_tour_url',
        'deed_number',
        'deed_date',
        'deed_issuer',
        'preview_deed_number',
        'preview_deed_date',
        'preview_deed_issuer',
        'listing_guidance',
        'preview_listing_guidance',
        'in_app_tour',
      ]) {
        final current = (row[key] ?? '').toString().trim();
        final fallback = (request[key] ?? '').toString().trim();
        if (current.isEmpty && fallback.isNotEmpty) row[key] = request[key];
      }
    }
    stampRow(row);
    return row;
  }

  /// Normalizes property and legacy request media into the property-row shape.
  static void stampRow(Map row) {
    final payloadMap = <String, dynamic>{
      ...?guidanceMap(row['payload']),
      ...?guidanceMap(row['payload_json']),
    };
    final payloadGuidance = guidanceMap(payloadMap['listing_guidance']);
    final propertyGuidance = guidanceMap(
      row['listing_guidance'] ?? row['preview_listing_guidance'],
    );
    final guidance = <String, dynamic>{
      ...?payloadGuidance,
      ...?propertyGuidance,
    };
    if (guidance.isNotEmpty) row['listing_guidance'] = guidance;
    final mediaPayload = <String, dynamic>{...payloadMap};
    for (final entry in row.entries) {
      if (entry.key is String) {
        final value = entry.value;
        if (value == null ||
            (value is String && value.trim().isEmpty) ||
            (value is List && value.isEmpty) ||
            (value is Map && value.isEmpty)) {
          continue;
        }
        mediaPayload[entry.key as String] = value;
      }
    }
    if (guidance.isNotEmpty) mediaPayload['listing_guidance'] = guidance;

    final fromEmbedded = ListingMediaUrls.imagePathsFromPropertyImages(
      row['property_images'],
    );
    final embeddedVideo =
        ListingMediaUrls.videoPathFromPropertyImages(row['property_images']);
    final fromPropertyRow = ListingMediaUrls.imagePathsFromPayload({
      'images': row['images'],
      'image_urls': row['image_urls'],
      'primary_image': row['image_url'] ?? row['primary_image'],
    });
    final fromPayload = ListingMediaUrls.imagePathsFromPayload({
      ...mediaPayload,
    });
    final merged = ListingMediaUrls.mergePathLists([
      fromEmbedded,
      fromPropertyRow,
      fromPayload,
    ]);

    if (merged.isNotEmpty) {
      row['images'] = merged;
      if ((row['image_url'] ?? '').toString().trim().isEmpty) {
        row['image_url'] = merged.first;
      }
      row['property_images'] = [
        for (var i = 0; i < merged.length; i++)
          <String, dynamic>{
            'path': merged[i],
            'file_name': merged[i],
            'sort_order': i,
          },
      ];
    }

    String? deliveryVideo;
    final deliveries = guidance['photographer_media_deliveries'];
    if (deliveries is List) {
      for (final delivery in deliveries) {
        if (delivery is! Map) continue;
        final value = (delivery['video_path'] ?? '').toString().trim();
        if (value.isNotEmpty) {
          deliveryVideo = value;
          break;
        }
      }
    }
    final guidanceVideo =
        (guidance['photographer_video_path'] ?? '').toString().trim();
    final propertyVideo = (row['video_url'] ?? '').toString().trim();
    final video = deliveryVideo ??
        (guidanceVideo.isEmpty ? null : guidanceVideo) ??
        (propertyVideo.isEmpty ? null : propertyVideo) ??
        embeddedVideo ??
        ListingMediaUrls.videoPathFromPayload(mediaPayload);
    if ((video ?? '').trim().isNotEmpty) row['video_url'] = video!.trim();

    final tour = ListingMediaUrls.virtualTourFromPayload({
      ...mediaPayload,
    });
    if ((row['virtual_tour_url'] ?? '').toString().trim().isEmpty &&
        (tour ?? '').trim().isNotEmpty) {
      row['virtual_tour_url'] = tour!.trim();
    }

    for (final key in const ['deed_number', 'deed_date', 'deed_issuer']) {
      final current = (row[key] ?? '').toString().trim();
      final aliases = switch (key) {
        'deed_number' => const ['preview_deed_number', 'request_deed_number'],
        'deed_date' => const ['preview_deed_date', 'request_deed_date'],
        _ => const ['preview_deed_issuer'],
      };
      final fallback = [
        payloadMap[key],
        row[key],
        for (final alias in aliases) payloadMap[alias],
        for (final alias in aliases) row[alias],
      ].map((value) => (value ?? '').toString().trim()).firstWhere(
            (value) => value.isNotEmpty,
            orElse: () => '',
          );
      if (current.isEmpty && fallback.isNotEmpty) row[key] = fallback;
    }
  }

  static Future<Map<String, dynamic>> resolveRequest(
    SupabaseClient sb, {
    required Map<String, dynamic> request,
    Map<String, dynamic>? property,
  }) async {
    final row = resolveRow(property: property, request: request);
    await hydratePropertyRows(sb, [row]);
    stampRow(row);
    return row;
  }

  static Future<void> hydratePropertyRows(
    SupabaseClient sb,
    List<Map> rows,
  ) async {
    if (rows.isEmpty) return;

    final need = <String>[];
    for (final r in rows) {
      final id = (r['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final paths = ListingMediaUrls.imagePathsFromPropertyImages(
        r['property_images'],
      );
      if (paths.isEmpty) need.add(id);
    }

    if (need.isNotEmpty) {
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
    }

    for (final r in rows) {
      stampRow(r);
    }
  }
}
