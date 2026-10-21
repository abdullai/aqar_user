import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/listing/image_perceptual_hash.dart';

/// تسجيل بصمات صور الإعلان للمراجعة؛ لا يحجب النشر ولا يعطّله أبداً.
abstract final class ListingImageSimilarityService {
  static Future<void> register({
    required List<({Uint8List bytes, String sha256})> images,
    String? propertyId,
    String? requestId,
  }) async {
    try {
      final entries = <Map<String, Object>>[];
      var idx = 0;
      for (final img in images.take(30)) {
        final v = await ImagePerceptualHash.computeAsync(img.bytes);
        idx++;
        if (v.isEmpty) continue;
        entries.add({'i': idx, 'v': v, 's': img.sha256});
      }
      if (entries.isEmpty) return;
      await Supabase.instance.client.rpc(
        'register_listing_image_hashes',
        params: {
          'p_hashes': entries,
          'p_property_id': _uuidOrNull(propertyId),
          'p_request_id': _uuidOrNull(requestId),
        },
      );
    } catch (_) {}
  }

  static String? _uuidOrNull(String? v) {
    final s = (v ?? '').trim();
    return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(s) ? s : null;
  }
}
