import 'dart:typed_data';

import '../core/listing/listing_media_seal.dart';

/// توافق قديم: لا تُعاد ضغط الصورة ولا تُرسم نصوص على البكسل.
/// الختم الحقيقي هو تجزئة SHA-256 عبر [ListingMediaSeal].
class WatermarkService {
  static Future<Uint8List> addTextWatermark(
    Uint8List inputBytes, {
    String text = '',
    int margin = 16,
    int fontSize = 24,
    int opacity = 170,
  }) async {
    // الإبقاء على البايتات الأصلية — إعادة decode/encode كانت تدمّر الصفاء.
    return Uint8List.fromList(inputBytes);
  }

  static ListingSealedBytes seal(Uint8List inputBytes, {String name = ''}) {
    return ListingMediaSeal.preserve(inputBytes, name: name);
  }
}
